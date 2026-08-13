param(
    [string]$OutputDirectory = "release",
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

    # A universal debug APK contains the Dart kernel, debug engine and native
    # libraries for every ABI. Split release APKs remove those debug artifacts
    # and let users download only the native architecture their device needs.
    & $FlutterPath build apk --release --split-per-abi
    if ($LASTEXITCODE -ne 0) { throw "flutter release build failed" }

    $destination = Join-Path $projectRoot $OutputDirectory
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    Copy-Item "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" `
        (Join-Path $destination "Myune-music-for-Android-arm64-v8a.apk") -Force
    Copy-Item "build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk" `
        (Join-Path $destination "Myune-music-for-Android-armeabi-v7a.apk") -Force

    Get-ChildItem $destination -Filter "*.apk" |
        Select-Object Name, @{Name = "SizeMB"; Expression = { [math]::Round($_.Length / 1MB, 1) }}
} finally {
    Pop-Location
}
