<#
.SYNOPSIS
  Knightly's releases, with Shorebird.

.DESCRIPTION
  .\release.ps1 patch
      A silent fix: a Shorebird patch (Dart code only) for the release of the version in
      pubspec.yaml, on the stable track. Phones get it in the background, at the next restart.

  .\release.ps1 major [-Notes "What's new"] [-Device <adb id>]
      A new release: reads the version from pubspec.yaml (bump it first, see README.md), runs
      shorebird release android (APK, arm64), then publishes it on GitHub (itsabubakar/knightly-
      releases, tagged v<version>, the APK attached): installed apps offer to update to it. With
      -Device, also installs it on that phone with adb.

  Needs: shorebird and gh (GitHub CLI, signed in: gh auth login) on the PATH.
#>
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateSet('patch', 'major')]
  [string]$Mode,

  # The release notes shown in the app's "New version available" dialog (major only).
  [string]$Notes = '',

  # An adb device id (adb devices) to install the new release on (major only).
  [string]$Device = ''
)

# Programs (shorebird, gh, adb) write their progress and messages to stderr, which Windows PowerShell
# 5.1 would take as errors if it stopped on them: their exit codes tell whether they failed.
$ErrorActionPreference = 'Continue'
Set-Location -Path $PSScriptRoot

$ReleasesRepo = 'itsabubakar/knightly-releases'
$FlutterVersion = '3.50.0'
$DartDefines = @(
  '--dart-define=LICHESS_HOST=lichess.org',
  '--dart-define=LICHESS_WS_HOST=socket.lichess.org'
)

# The version in pubspec.yaml, e.g. 1.0.1+010001.
$versionLine = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)'
if (-not $versionLine) { throw 'No version found in pubspec.yaml.' }
$semver = $versionLine.Matches[0].Groups[1].Value
$buildText = $versionLine.Matches[0].Groups[2].Value
$build = [int]$buildText
$version = "$semver+$buildText"
# Shorebird names the release without the build number's leading zeros: 1.0.1+10001.
$shorebirdVersion = "$semver+$build"

function Invoke-Checked([string]$what, [scriptblock]$command) {
  & $command
  if ($LASTEXITCODE -ne 0) { throw "$what failed (exit code $LASTEXITCODE)." }
}

if ($Mode -eq 'patch') {
  Write-Host "Patching release $shorebirdVersion (stable track)..." -ForegroundColor Cyan
  Invoke-Checked 'shorebird patch' {
    shorebird patch --platforms=android --release-version=$shorebirdVersion --track=stable -- @DartDefines
  }
  Write-Host 'Patch published: phones get it in the background, then on their next restart.' -ForegroundColor Green
  exit 0
}

# major: a new release.
$tag = "v$version"
gh release view $tag --repo $ReleasesRepo 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
  throw "$tag is already on GitHub: bump the version in pubspec.yaml first (see README.md)."
}

Write-Host "Releasing $version with Shorebird..." -ForegroundColor Cyan
Invoke-Checked 'shorebird release' {
  shorebird release android --artifact apk --target-platform android-arm64 --flutter-version=$FlutterVersion -- @DartDefines
}

$builtApk = 'build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path $builtApk)) { throw "No APK at $builtApk." }
$apk = Join-Path $env:TEMP "knightly-$semver.apk"
Copy-Item $builtApk $apk -Force -ErrorAction Stop

if ($Notes -eq '') { $Notes = "Knightly $semver" }
Write-Host "Publishing $tag on GitHub ($ReleasesRepo)..." -ForegroundColor Cyan
Invoke-Checked 'gh release create' {
  gh release create $tag $apk --repo $ReleasesRepo --title "Knightly $semver" --notes $Notes
}
Write-Host "Published ${tag}: installed apps offer to update to it." -ForegroundColor Green

if ($Device -ne '') {
  Write-Host "Installing on $Device..." -ForegroundColor Cyan
  Invoke-Checked 'adb install' { adb -s $Device install -r $builtApk }
}
