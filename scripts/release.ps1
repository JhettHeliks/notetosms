# Automated Release Script for notetosms (PowerShell)
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$TargetVersion,

    [Parameter(Position = 1)]
    [string]$ReleaseNotes
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Get-Item $PSScriptRoot).Parent.FullName
Set-Location $ProjectRoot

# Strip leading 'v'
$Version = $TargetVersion.TrimStart('v')
$TagName = "v$Version"
$PubspecPath = Join-Path $ProjectRoot "pubspec.yaml"
$ReleaseNotesFile = Join-Path $ProjectRoot "RELEASE_NOTES.md"

if (-not (Test-Path $PubspecPath)) {
    Write-Error "pubspec.yaml not found at $PubspecPath"
    exit 1
}

# Resolve Release Notes
if (-not $ReleaseNotes -and (Test-Path $ReleaseNotesFile)) {
    $ReleaseNotes = Get-Content $ReleaseNotesFile -Raw
}

$PubspecContent = Get-Content $PubspecPath -Raw
if ($PubspecContent -match 'version:\s*([0-9]+\.[0-9]+\.[0-9]+[a-zA-Z0-9\.\-]*)(\+([0-9]+))?') {
    $CurrentBuild = if ($Matches[3]) { [int]$Matches[3] } else { 0 }
} else {
    $CurrentBuild = 0
}

$NewBuild = $CurrentBuild + 1
$TargetVersionString = "$Version+$NewBuild"

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "          notetosms Release Automation Pipeline       " -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "Target Version : $Version" -ForegroundColor Yellow
Write-Host "Build Number   : $NewBuild" -ForegroundColor Yellow
Write-Host "Git Tag        : $TagName" -ForegroundColor Yellow
if ($ReleaseNotes) {
    Write-Host "Release Notes  : Provided" -ForegroundColor Yellow
}
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Update version in pubspec.yaml
Write-Host "[1/5] Updating pubspec.yaml to version: $TargetVersionString..." -ForegroundColor Yellow
$UpdatedPubspec = $PubspecContent -replace 'version:\s*[^\r\n]+', "version: $TargetVersionString"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($PubspecPath, $UpdatedPubspec, $Utf8NoBom)

# 2. Run static analysis
Write-Host "[2/5] Running static analysis check..." -ForegroundColor Yellow
flutter analyze lib/
if ($LASTEXITCODE -ne 0) {
    Write-Error "Static analysis failed. Aborting release."
    exit $LASTEXITCODE
}

# 3. Stage changes
Write-Host "[3/5] Staging pubspec.yaml and release assets..." -ForegroundColor Yellow
git add pubspec.yaml
if (Test-Path $ReleaseNotesFile) {
    git add $ReleaseNotesFile
}

# 4. Commit and Tag
Write-Host "[4/5] Creating commit and tag $TagName..." -ForegroundColor Yellow
git commit -m "chore(release): bump version to $TagName"
if ($ReleaseNotes) {
    git tag -a $TagName -m "Release $TagName" -m "$ReleaseNotes"
} else {
    git tag -a $TagName -m "Release $TagName"
}

# 5. Push branch and tag to origin
Write-Host "[5/5] Pushing to origin..." -ForegroundColor Yellow
$CurrentBranch = git rev-parse --abbrev-ref HEAD
git push origin $CurrentBranch
git push origin $TagName

Write-Host ""
Write-Host "======================================================" -ForegroundColor Green
Write-Host "  Successfully released $TagName and pushed to GitHub! " -ForegroundColor Green
Write-Host "  GitHub Actions CI/CD release workflow is now running. " -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Green
