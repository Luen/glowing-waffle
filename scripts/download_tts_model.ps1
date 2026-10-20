param(
    [Parameter(Position = 0)]
    [ValidateSet("kokoro", "kitten")]
    [string]$Model = "kokoro",

    # Old spelling of the model argument; still accepted.
    [switch]$Kitten
)
# Download a sherpa-onnx TTS model and place the files scripts/smoke_tts.py
# needs into the assets directory of the app.
#   kokoro (default)  Kokoro v1.0   -> assets/tts/         (~340MB)
#   kitten            Kitten nano   -> assets/tts_kitten/  (~25MB)
# Needed by the smoke test and by offline development builds; the app itself
# downloads the model on first run (issues #6, #7).
# See: https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/kokoro.html

$ErrorActionPreference = "Stop"

if ($Kitten) {
    $Model = "kitten"
}

if ($Model -eq "kitten") {
    $name = "kitten-nano-en-v0_2-fp16"
    $assetsDir = "assets\tts_kitten"
    $files = @("model.fp16.onnx", "tokens.txt", "voices.bin")
    $size = "~25MB"
} else {
    $name = "kokoro-multi-lang-v1_0"
    $assetsDir = "assets\tts"
    $files = @("model.onnx", "tokens.txt", "voices.bin", "lexicon-us-en.txt")
    $size = "~340MB"
}
$url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/$name.tar.bz2"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$assetsTts = Join-Path $projectRoot $assetsDir
$tempDir = Join-Path $env:TEMP "tts-model-download"

Write-Host "Downloading $name ($size)..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

$archivePath = Join-Path $tempDir "$name.tar.bz2"
if (-not (Test-Path $archivePath)) {
    Invoke-WebRequest -Uri $url -OutFile $archivePath -UseBasicParsing
}

Write-Host "Extracting archive..." -ForegroundColor Cyan
$extractDir = Join-Path $tempDir $name
if (-not (Test-Path $extractDir)) {
    # Windows 10+ has tar; otherwise use bzip2 + tar if available
    $tar = Get-Command tar -ErrorAction SilentlyContinue
    if ($tar) {
        Push-Location $tempDir
        tar -xjf "$name.tar.bz2"
        Pop-Location
    } else {
        Write-Host "Could not find 'tar'. Install it or extract manually:"
        Write-Host "  1. Extract $name.tar.bz2 (e.g. with 7-Zip)"
        Write-Host "  2. Copy $($files -join ', ') from $name/ to $assetsTts"
        exit 1
    }
}

New-Item -ItemType Directory -Force -Path $assetsTts | Out-Null
foreach ($f in $files) {
    $src = Join-Path $extractDir $f
    $dst = Join-Path $assetsTts $f
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $dst -Force
        Write-Host "  Copied $f" -ForegroundColor Green
    } else {
        Write-Host "  Warning: $f not found in archive" -ForegroundColor Yellow
    }
}

$zip = Join-Path $assetsTts "espeak-ng-data.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path (Join-Path $extractDir "espeak-ng-data") -DestinationPath $zip
Write-Host "  Created espeak-ng-data.zip" -ForegroundColor Green

Write-Host "Done. $name assets are in $assetsTts" -ForegroundColor Green
Write-Host "Run: flutter pub get && flutter run -d android  (or -d chrome for web)" -ForegroundColor Cyan
