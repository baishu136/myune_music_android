param(
    [string]$OutputDirectory = "dist",
    [string]$FlutterPath = "",
    [switch]$SkipPubGet
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

function Read-ReleaseVersion {
    $pubspec = Get-Content -LiteralPath (Join-Path $projectRoot "pubspec.yaml") -Raw
    $versionMatches = [regex]::Matches(
        $pubspec,
        '(?m)^version:[ \t]*(\d+\.\d+\.\d+)\+(\d+)[ \t]*\r?$'
    )
    if ($versionMatches.Count -ne 1 -or [regex]::Matches($pubspec, '(?m)^version:').Count -ne 1) {
        throw "pubspec.yaml must contain exactly one version: x.y.z+build"
    }
    [PSCustomObject]@{
        Version = $versionMatches[0].Groups[1].Value
        Build = $versionMatches[0].Groups[2].Value
    }
}

# Reject invalid metadata and immutable archive collisions before invoking Flutter.
$releaseVersion = Read-ReleaseVersion
$version = $releaseVersion.Version
$build = $releaseVersion.Build
$destination = if ([IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory
} else {
    Join-Path $projectRoot $OutputDirectory
}
$apkPath = Join-Path $destination "Myune-Music-$version-android.$build-arm64-v8a.apk"
if (Test-Path -LiteralPath $apkPath) {
    throw "Release archive already exists: $apkPath. Increment the build or choose a new output directory."
}

if ([string]::IsNullOrWhiteSpace($FlutterPath)) {
    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if ($null -ne $flutterCommand) {
        $FlutterPath = $flutterCommand.Source
    } else {
        $userFlutter = Join-Path $env:USERPROFILE "develop\flutter\bin\flutter.bat"
        if (Test-Path -LiteralPath $userFlutter) {
            $FlutterPath = $userFlutter
        } else {
            throw "Flutter SDK was not found. Pass -FlutterPath with flutter.bat's full path."
        }
    }
}

Push-Location $projectRoot
try {
    if (-not $SkipPubGet) {
        & $FlutterPath pub get
        if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
    }

    # Build only the requested ABI, not three binaries followed by copying one.
    & $FlutterPath build apk --release --target-platform android-arm64 --split-per-abi
    if ($LASTEXITCODE -ne 0) { throw "flutter release build failed" }

    $builtVersion = Read-ReleaseVersion
    if ($builtVersion.Version -ne $version -or $builtVersion.Build -ne $build) {
        throw "pubspec.yaml version changed during the build; refusing to label the APK."
    }
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    # The exclusive copy also rejects a file created after the preflight check.
    [IO.File]::Copy(
        (Join-Path $projectRoot "build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"),
        $apkPath,
        $false
    )

    Get-Item -LiteralPath $apkPath |
        Select-Object FullName, Length, @{Name = "SizeMiB"; Expression = { [math]::Round($_.Length / 1MB, 2) }}
    Write-Output ("SHA256: {0}" -f (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash)
} finally {
    Pop-Location
}
