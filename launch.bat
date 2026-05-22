@echo off
setlocal EnableDelayedExpansion
REM Supplier Hub launcher (auto-update + restart safe).
REM Cift tikla shortcut "cmd.exe /K launch.bat" -> pencere her halukarda acik kalir.

cd /d "%~dp0"

echo ===================================================
echo   Supplier Hub
echo ===================================================
echo.
echo Klasor: %CD%
echo.

REM Node check
where node >nul 2>&1
if errorlevel 1 (
  echo HATA: Node bulunamadi. Yeniden install yap:
  echo   iwr -useb https://www.flowiqa.com/install/supplier-hub.ps1 ^| iex
  echo.
  pause
  exit /b 1
)

REM dist/server.js check
if not exist "dist\server.js" (
  echo HATA: dist\server.js yok - kurulum bozuk. Yeniden install yap.
  echo.
  pause
  exit /b 1
)

REM Update check + auto-apply (CRLF/BOM-aware helper)
echo Yeni surum kontrol ediliyor...
set UPDATE_STATUS=
if exist "scripts\check-update.js" (
  for /f "tokens=*" %%s in ('node scripts\check-update.js 2^>nul') do set UPDATE_STATUS=%%s
)

set UPDATED=0
if "!UPDATE_STATUS:~0,12!"=="NEED_UPDATE:" (
  set REMOTE_VERSION=!UPDATE_STATUS:~12!
  echo   Yeni surum: !REMOTE_VERSION!, guncelleniyor...

  REM Lisans key cache'ten oku
  set LICENSE_KEY=
  if exist "scripts\read-license-key.js" (
    for /f "tokens=*" %%k in ('node scripts\read-license-key.js 2^>nul') do set LICENSE_KEY=%%k
  )

  if "!LICENSE_KEY!"=="" (
    echo   UYARI: Lisans cache yok, guncelleme atlandi.
  ) else (
    REM Eski server kill
    for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":3100 " ^| findstr "LISTENING"') do taskkill /PID %%p /F >nul 2>&1

    REM Re-run installer (TARGET=cwd, key env) — ilerleme console'a (npm install uzun)
    echo   ^(Bu birkac dakika surebilir — npm install, tarball extract, vs.^)
    powershell -ExecutionPolicy Bypass -Command "$env:TARGET='%CD%'; $env:LICENSE_KEY='!LICENSE_KEY!'; iwr -useb https://www.flowiqa.com/install/supplier-hub.ps1 | iex"
    if not errorlevel 1 (
      echo   Guncelleme basarili.
      set UPDATED=1
    ) else (
      echo   Guncelleme basarisiz, eski surum ile devam.
    )
  )
) else if "!UPDATE_STATUS:~0,3!"=="OK:" (
  set LOCAL_VERSION=!UPDATE_STATUS:~3!
  echo   Guncel: !LOCAL_VERSION!
)
echo.

REM Update yapildiysa self re-exec (yeni dist + temiz state + yeni launch.bat)
if "!UPDATED!"=="1" (
  echo   Pencere yeniden aciliyor yeni surumle...
  start "" cmd /K ""%~f0""
  exit /b
)

REM Server baslat ve tarayicida ac
echo Server baslatiliyor: http://localhost:3100
echo.
echo ^(Server kapatmak icin: bu pencereyi kapat veya Ctrl+C^)
echo.

REM 3 saniye sonra tarayici ac
start "" /b cmd /c "timeout /t 3 /nobreak >nul && start http://localhost:3100"

REM Server'i foreground'da calistir (terminal acik kalir, hata gorunur)
node server.js

echo.
echo Server kapandi.
pause
