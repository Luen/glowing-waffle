# Download Kokoro TTS model (sherpa-onnx) and place model.onnx, tokens.txt, voices.bin into assets/tts/
# Required for native (Android/iOS) TTS. See: https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/kokoro.html

$ErrorActionPreference = "Stop"
$url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$assetsTts = Join-Path $projectRoot "assets\tts"
$tempDir = Join-Path $env:TEMP "kokoro-tts-download"

Write-Host "Downloading Kokoro TTS model (v1_0, ~340MB)..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

$archivePath = Join-Path $tempDir "kokoro-multi-lang-v1_0.tar.bz2"
if (-not (Test-Path $archivePath)) {
    Invoke-WebRequest -Uri $url -OutFile $archivePath -UseBasicParsing
}

Write-Host "Extracting archive..." -ForegroundColor Cyan
$extractDir = Join-Path $tempDir "kokoro-multi-lang-v1_0"
if (-not (Test-Path $extractDir)) {
    # Windows 10+ has tar; otherwise use bzip2 + tar if available
    $tar = Get-Command tar -ErrorAction SilentlyContinue
    if ($tar) {
        Push-Location $tempDir
        tar -xjf "kokoro-multi-lang-v1_0.tar.bz2"
        Pop-Location
    } else {
        Write-Host "Could not find 'tar'. Install it or extract manually:"
        Write-Host "  1. Extract kokoro-multi-lang-v1_0.tar.bz2 (e.g. with 7-Zip)"
        Write-Host "  2. Copy model.onnx, tokens.txt, voices.bin from kokoro-multi-lang-v1_0/ to $assetsTts"
        exit 1
    }
}

New-Item -ItemType Directory -Force -Path $assetsTts | Out-Null
$files = @("model.onnx", "tokens.txt", "voices.bin")
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

Write-Host "Done. Kokoro assets are in $assetsTts" -ForegroundColor Green
Write-Host "Run: flutter pub get && flutter run -d android  (or -d chrome for web)" -ForegroundColor Cyan
