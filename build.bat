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

if not exist "dist" mkdir "dist"
if errorlevel 1 exit /b 1
copy /Y "build\app\outputs\flutter-apk\app-release.apk" "dist\FC_Career_Live.apk" >nul
if errorlevel 1 exit /b 1

echo APK gerado em: %~dp0dist\FC_Career_Live.apk
exit /b 0
