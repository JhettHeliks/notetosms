# Release Helper Script for notetosms (PowerShell)
param (
    [Parameter(Position = 0)]
    [string]$NewVersion,

    [switch]$Push,

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Get-Item $PSScriptRoot).Parent.FullName
Set-Location $ProjectRoot

$PubspecPath = Join-Path $ProjectRoot "pubspec.yaml"
$PubspecContent = Get-Content $PubspecPath -Raw

if ($PubspecContent -match 'version:\s*([0-9]+\.[0-9]+\.[0-9]+[a-zA-Z0-9\.\-]*)(\+([0-9]+))?') {
    $CurrentVersion = $Matches[1]
    $CurrentBuild = if ($Matches[3]) { [int]$Matches[3] } else { 1 }
} else {
    Write-Error "Could not parse current version from pubspec.yaml."
    exit 1
}

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "             notetosms Release Manager                " -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "Current Version: v$CurrentVersion (Build $CurrentBuild)"

if (-not $NewVersion) {
    Write-Host ""
    Write-Host "Select version bump type or type custom version (e.g. 1.0.1, 1.1.0-beta.1):"
    $InputVer = Read-Host "Target Version (leave blank for patch bump)"
    if ([string]::IsNullOrWhiteSpace($InputVer)) {
        # Auto bump patch
        $Parts = $CurrentVersion.Split('.')
        $Major = [int]$Parts[0]
        $Minor = [int]$Parts[1]
        $Patch = [int]($Parts[2].Split('-')[0]) + 1
        $NewVersion = "$Major.$Minor.$Patch"
    } else {
        $NewVersion = $InputVer.TrimStart('v')
    }
}

$NewBuild = $CurrentBuild + 1
$TargetVersionString = "$NewVersion+$NewBuild"
$TagName = "v$NewVersion"

Write-Host ""
Write-Host "Target Version: $NewVersion" -ForegroundColor Yellow
Write-Host "Target Build  : $NewBuild" -ForegroundColor Yellow
Write-Host "Git Tag       : $TagName" -ForegroundColor Yellow
Write-Host ""

if ($DryRun) {
    Write-Host "[DryRun] Would update pubspec.yaml to $TargetVersionString, commit, and tag $TagName." -ForegroundColor Magenta
    exit 0
}

# 1. Update pubspec.yaml
Write-Host "[1/4] Updating pubspec.yaml..." -ForegroundColor Yellow
$UpdatedPubspec = $PubspecContent -replace 'version:\s*[^\r\n]+', "version: $TargetVersionString"
$UpdatedPubspec | Out-File -FilePath $PubspecPath -Encoding utf8 -NoNewline

# 2. Run static analysis check
Write-Host "[2/4] Running code quality validation..." -ForegroundColor Yellow
flutter analyze
if ($LASTEXITCODE -ne 0) {
    Write-Error "Flutter analysis failed. Aborting release."
    exit $LASTEXITCODE
}

# 3. Git commit & tag
Write-Host "[3/4] Creating git commit and tag $TagName..." -ForegroundColor Yellow
git add pubspec.yaml
git commit -m "chore(release): bump version to $TagName"
git tag -a $TagName -m "Release $TagName"

Write-Host "  -> Tag $TagName created successfully." -ForegroundColor Green

# 4. Push to remote
if ($Push) {
    Write-Host "[4/4] Pushing commits and tag $TagName to origin..." -ForegroundColor Yellow
    git push origin main --tags
    Write-Host "  -> Pushed! GitHub Actions release workflow has been triggered." -ForegroundColor Green
} else {
    Write-Host "[4/4] Release prepared locally." -ForegroundColor Cyan
    Write-Host "To trigger GitHub Releases CI/CD, run:" -ForegroundColor White
    Write-Host "    git push origin main --tags" -ForegroundColor Green
}

Write-Host ""
Write-Host "======================================================" -ForegroundColor Green
Write-Host "           Release $TagName Ready!                    " -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Green
