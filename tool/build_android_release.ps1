param(
    [string]$OutputDirectory = "dist",
    [string]$FlutterPath = ""
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
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
    & $FlutterPath pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }

    # Build only the requested ABI, not three binaries followed by copying one.
    & $FlutterPath build apk --release --target-platform android-arm64 --split-per-abi
    if ($LASTEXITCODE -ne 0) { throw "flutter release build failed" }

    $versionMatch = [regex]::Match(
        (Get-Content -LiteralPath (Join-Path $projectRoot "pubspec.yaml") -Raw),
        '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$'
    )
    if (-not $versionMatch.Success) { throw "pubspec.yaml must contain version: x.y.z+build" }
    $version = $versionMatch.Groups[1].Value
    $build = $versionMatch.Groups[2].Value
    $destination = if ([IO.Path]::IsPathRooted($OutputDirectory)) {
        $OutputDirectory
    } else {
        Join-Path $projectRoot $OutputDirectory
    }
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    $apkPath = Join-Path $destination "Myune-Music-$version-android.$build-arm64-v8a.apk"
    Copy-Item "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" `
        $apkPath -Force

    Get-Item -LiteralPath $apkPath |
        Select-Object FullName, Length, @{Name = "SizeMiB"; Expression = { [math]::Round($_.Length / 1MB, 2) }}
    Write-Output ("SHA256: {0}" -f (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash)
} finally {
    Pop-Location
}
