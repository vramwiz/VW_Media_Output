@echo off
setlocal

set "SOURCE_DIR=C:\ProgramData\aviutl2\Plugin\VW_Media_Output"
set "OUTPUT_DIR=%~dp0"
set "ZIP_NAME=VW_Media_Output.zip"
set "ZIP_PATH=%OUTPUT_DIR%%ZIP_NAME%"
set "TEMP_ROOT=%TEMP%\VW_Media_Output_release_zip"
set "TEMP_DIR=%TEMP_ROOT%\VW_Media_Output"

if not exist "%SOURCE_DIR%\" (
  echo Source folder was not found:
  echo   %SOURCE_DIR%
  exit /b 1
)

if exist "%ZIP_PATH%" del /Q "%ZIP_PATH%"
if exist "%TEMP_ROOT%\" rmdir /S /Q "%TEMP_ROOT%"

mkdir "%TEMP_DIR%"
if errorlevel 1 (
  echo Failed to create temporary folder:
  echo   %TEMP_DIR%
  exit /b 1
)

robocopy "%SOURCE_DIR%" "%TEMP_DIR%" /E /XF *.ini >nul
if errorlevel 8 (
  echo Failed to copy files for zip:
  echo   %SOURCE_DIR%
  rmdir /S /Q "%TEMP_ROOT%"
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Compress-Archive -Path '%TEMP_DIR%' -DestinationPath '%ZIP_PATH%' -Force"

if errorlevel 1 (
  echo Failed to create zip:
  echo   %ZIP_PATH%
  rmdir /S /Q "%TEMP_ROOT%"
  exit /b 1
)

rmdir /S /Q "%TEMP_ROOT%"

echo Created:
echo   %ZIP_PATH%
endlocal
