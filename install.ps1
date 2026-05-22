# Supplier Hub - Windows tek satir kurulum
# Kullanim:
#   iwr -useb https://raw.githubusercontent.com/esenbora/supplier-hub/main/install.ps1 | iex
# Ozel hedef:
#   $env:TARGET="C:\etsy-tool"; iwr ... | iex

$ErrorActionPreference = "Stop"

$REPO_URL = "https://github.com/esenbora/supplier-hub.git"
$BRANCH = if ($env:BRANCH) { $env:BRANCH } else { "main" }
$TARGET = if ($env:TARGET) { $env:TARGET } else { Join-Path $HOME "supplier-hub" }

Write-Host "=== Supplier Hub - Windows tek satir kurulum ===" -ForegroundColor Cyan
Write-Host "Hedef: $TARGET"

function Need($c) { $null -ne (Get-Command $c -ErrorAction SilentlyContinue) }
function Write-Utf8NoBom($path, $content) {
  [System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))
}
function RefreshPath {
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
              [System.Environment]::GetEnvironmentVariable("Path","User")
}

if (-not (Need winget)) {
  Write-Host "HATA: winget yok. Windows 10 1809+ veya Windows 11 gerekli." -ForegroundColor Red
  exit 1
}

if (-not (Need git)) {
  Write-Host ">> Git kuruluyor (winget)..." -ForegroundColor Yellow
  winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
  RefreshPath
  if (-not (Need git)) {
    Write-Host "Git kuruldu ama PATH'te yok. PowerShell'i kapat-ac, scripti tekrar calistir." -ForegroundColor Red
    exit 1
  }
}
Write-Host "   git: $(git --version)"

# Clone / pull
if (Test-Path (Join-Path $TARGET ".git")) {
  Write-Host ">> Mevcut klasor, $BRANCH branch'ine geciliyor + guncelleniyor..." -ForegroundColor Yellow
  Push-Location $TARGET
  # Single-branch clone'lardaki refspec sorununu coz
  git remote set-branches --add origin $BRANCH 2>$null
  git fetch origin $BRANCH --tags --quiet
  if ($LASTEXITCODE -ne 0) {
    Write-Host "HATA: git fetch basarisiz. Klasoru elle silip tekrar dene." -ForegroundColor Red
    Pop-Location
    exit 1
  }
  git checkout -B $BRANCH "origin/$BRANCH"
  git pull --ff-only origin $BRANCH
  Pop-Location
} elseif (Test-Path $TARGET) {
  Write-Host "HATA: $TARGET var ama git deposu degil." -ForegroundColor Red
  exit 1
} else {
  Write-Host ">> Clone: $REPO_URL ($BRANCH)" -ForegroundColor Yellow
  git clone --branch $BRANCH $REPO_URL $TARGET
}

Set-Location $TARGET

# Older PowerShell installs may have written config.json with a UTF-8 BOM.
# Normalize it before setup.ps1 so reinstall does not preserve the broken bytes.
$configPath = Join-Path $TARGET "config.json"
if (Test-Path $configPath) {
  Write-Utf8NoBom $configPath ([System.IO.File]::ReadAllText($configPath))
}

# setup.ps1 calistir
if (-not (Test-Path "setup.ps1")) {
  Write-Host "HATA: setup.ps1 yok" -ForegroundColor Red
  exit 1
}
& powershell -ExecutionPolicy Bypass -File ".\setup.ps1"

Write-Host ""
Write-Host "=== TUMU TAMAM ===" -ForegroundColor Green
Write-Host "Klasor: $TARGET"
Write-Host ""
Write-Host "Sirayla:"
Write-Host "  notepad $TARGET\.env       (GEMINI + OPENROUTER key)"
Write-Host "  $TARGET\start-browser.bat  (etsy + pinterest login)"
Write-Host "  $TARGET\start.bat          (server :3000)"
Write-Host "  start http://localhost:3000"
