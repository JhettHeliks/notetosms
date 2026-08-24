# PowerShell Build & Packaging Script for notetosms
param (
    [ValidateSet("release", "beta")]
    [string]$Mode = "release",

    [switch]$SplitPerAbi,

    [switch]$SkipCodegen,

    [switch]$Clean
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Get-Item $PSScriptRoot).Parent.FullName

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "       notetosms Build & Artifact Packaging" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "Project Root: $ProjectRoot"
Write-Host "Build Mode  : $Mode"
Write-Host "Split ABI   : $SplitPerAbi"
Write-Host ""

Set-Location $ProjectRoot

# Determine destination directory
$DestDir = if ($Mode -eq "beta") {
    Join-Path $ProjectRoot "dist/betas"
} else {
    Join-Path $ProjectRoot "dist/releases"
}

if (!(Test-Path $DestDir)) {
    New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
}

# 1. Clean if requested
if ($Clean) {
    Write-Host "[1/4] Cleaning previous build artifacts..." -ForegroundColor Yellow
    flutter clean
} else {
    Write-Host "[1/4] Skipping clean (use -Clean to force clean build)" -ForegroundColor DarkGray
}

# 2. Run flutter_rust_bridge_codegen if available and not skipped
if (-not $SkipCodegen) {
    Write-Host "[2/4] Verifying Flutter Rust Bridge code generation..." -ForegroundColor Yellow
    if (Get-Command "flutter_rust_bridge_codegen" -ErrorAction SilentlyContinue) {
        flutter_rust_bridge_codegen generate
        Write-Host "  -> FRB code generation complete." -ForegroundColor Green
    } else {
        Write-Host "  -> flutter_rust_bridge_codegen not in PATH, using committed bindings." -ForegroundColor DarkYellow
    }
} else {
    Write-Host "[2/4] Skipping codegen (-SkipCodegen specified)" -ForegroundColor DarkGray
}

# 3. Compile Flutter APK
Write-Host "[3/4] Compiling Flutter APK ($Mode)..." -ForegroundColor Yellow
$BuildArgs = @("build", "apk", "--$Mode")
if ($SplitPerAbi) {
    $BuildArgs += "--split-per-abi"
}

flutter @BuildArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "Flutter build failed with exit code $LASTEXITCODE."
    exit $LASTEXITCODE
}

# 4. Copy and Sort Artifacts into dist/
Write-Host "[4/4] Sorting and verifying outputs into $DestDir..." -ForegroundColor Yellow

$ApkSourceDir = Join-Path $ProjectRoot "build/app/outputs/flutter-apk"
$CopiedFiles = @()

Get-ChildItem -Path $ApkSourceDir -Filter "*.apk" | ForEach-Object {
    $TargetFile = Join-Path $DestDir $_.Name
    Copy-Item -Path $_.FullName -Destination $TargetFile -Force
    
    # Calculate SHA-256
    $Sha256 = (Get-FileHash -Path $TargetFile -Algorithm SHA256).Hash.ToLower()
    $ShaFile = "$TargetFile.sha256"
    "$Sha256  $($_.Name)" | Out-File -FilePath $ShaFile -Encoding utf8

    $FileSizeMB = [math]::Round($_.Length / 1MB, 2)
    $CopiedFiles += [PSCustomObject]@{
        Artifact = $_.Name
        SizeMB   = "$FileSizeMB MB"
        SHA256   = $Sha256.Substring(0, 16) + "..."
        Location = $TargetFile
    }
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Green
Write-Host "          Build & Packaging Succeeded!                " -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Green
$CopiedFiles | Format-Table -AutoSize

Write-Host "Destination Directory: $DestDir" -ForegroundColor Cyan
