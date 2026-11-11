@echo off
setlocal
cd /d "%~dp0"
if errorlevel 1 exit /b 1

set "FLUTTER_BAT="
if defined FLUTTER_ROOT if exist "%FLUTTER_ROOT%\bin\flutter.bat" set "FLUTTER_BAT=%FLUTTER_ROOT%\bin\flutter.bat"
if not defined FLUTTER_BAT if exist "E:\flutter_sdk\bin\flutter.bat" set "FLUTTER_BAT=E:\flutter_sdk\bin\flutter.bat"
if not defined FLUTTER_BAT for %%F in (flutter.bat) do if not "%%~$PATH:F"=="" set "FLUTTER_BAT=%%~$PATH:F"

if not defined FLUTTER_BAT (
  echo Flutter nao encontrado. Defina FLUTTER_ROOT ou adicione flutter ao PATH.
  exit /b 1
)

call "%FLUTTER_BAT%" pub get
if errorlevel 1 exit /b 1

call "%FLUTTER_BAT%" build apk --release
if errorlevel 1 exit /b 1

set "APP_VERSION="
for /f "tokens=2 delims=: " %%V in ('findstr /b /c:"version:" pubspec.yaml') do set "APP_VERSION=%%V"
for /f "tokens=1 delims=+" %%V in ("%APP_VERSION%") do set "APP_VERSION=%%V"
if not defined APP_VERSION (
  echo Versao nao encontrada no pubspec.yaml.
  exit /b 1
)
set "APK_NAME=%APP_VERSION%_FC_Career_Live.apk"

if not exist "dist" mkdir "dist"
if errorlevel 1 exit /b 1
copy /Y "build\app\outputs\flutter-apk\app-release.apk" "dist\%APK_NAME%" >nul
if errorlevel 1 exit /b 1

echo APK gerado em: %~dp0dist\%APK_NAME%
exit /b 0
