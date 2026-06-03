@echo off
setlocal

set "SOURCE_DIR=C:\ProgramData\aviutl2\Plugin\VW_Media_Output"
set "OUTPUT_DIR=%~dp0"
set "ZIP_NAME=VW_Media_Output.zip"
set "ZIP_PATH=%OUTPUT_DIR%%ZIP_NAME%"

if not exist "%SOURCE_DIR%\" (
  echo Source folder was not found:
  echo   %SOURCE_DIR%
  exit /b 1
)

if exist "%ZIP_PATH%" del /Q "%ZIP_PATH%"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Compress-Archive -Path '%SOURCE_DIR%' -DestinationPath '%ZIP_PATH%' -Force"

if errorlevel 1 (
  echo Failed to create zip:
  echo   %ZIP_PATH%
  exit /b 1
)

echo Created:
echo   %ZIP_PATH%
endlocal
