@echo off
setlocal EnableExtensions

set "SOURCE_DIR=C:\ProgramData\aviutl2\Plugin\VW_Media_Output"
set "OUTPUT_DIR=%~dp0"
set "ZIP_NAME=VW_Media_Output.zip"
set "ZIP_PATH=%OUTPUT_DIR%%ZIP_NAME%"
set "TEMP_ROOT=%TEMP%\VW_Media_Output_release_%RANDOM%_%RANDOM%"
set "TEMP_DIR=%TEMP_ROOT%\VW_Media_Output"
set "TEMP_ZIP=%TEMP_ROOT%\%ZIP_NAME%"

if not exist "%SOURCE_DIR%\" (
  echo Source folder was not found:
  echo   %SOURCE_DIR%
  exit /b 1
)

rem Only runtime files belong in the release package. Do not copy INI or log files.
for %%F in (
  VW_Media_Output.auo2
  avutil-60.dll
  avcodec-62.dll
  avformat-62.dll
  avdevice-62.dll
  avfilter-11.dll
  swscale-9.dll
  swresample-6.dll
) do (
  if not exist "%SOURCE_DIR%\%%F" (
    echo Required runtime file was not found:
    echo   %SOURCE_DIR%\%%F
    exit /b 1
  )
)

for %%F in (
  "%~dp0..\LICENSE"
  "%~dp0THIRD_PARTY_NOTICES.txt"
  "%~dp0FFmpeg-LICENSE.txt"
  "%~dp0FFmpeg-README.txt"
) do (
  if not exist "%%~F" (
    echo Required license file was not found:
    echo   %%~F
    exit /b 1
  )
)

mkdir "%TEMP_DIR%" 2>nul
if errorlevel 1 (
  echo Failed to create temporary folder:
  echo   %TEMP_DIR%
  exit /b 1
)

for %%F in (
  VW_Media_Output.auo2
  avutil-60.dll
  avcodec-62.dll
  avformat-62.dll
  avdevice-62.dll
  avfilter-11.dll
  swscale-9.dll
  swresample-6.dll
) do (
  copy /Y "%SOURCE_DIR%\%%F" "%TEMP_DIR%\%%F" >nul
  if errorlevel 1 goto :copy_failed
)

copy /Y "%~dp0..\LICENSE" "%TEMP_DIR%\LICENSE.txt" >nul
if errorlevel 1 goto :copy_failed
copy /Y "%~dp0THIRD_PARTY_NOTICES.txt" "%TEMP_DIR%\THIRD_PARTY_NOTICES.txt" >nul
if errorlevel 1 goto :copy_failed
copy /Y "%~dp0FFmpeg-LICENSE.txt" "%TEMP_DIR%\FFmpeg-LICENSE.txt" >nul
if errorlevel 1 goto :copy_failed
copy /Y "%~dp0FFmpeg-README.txt" "%TEMP_DIR%\FFmpeg-README.txt" >nul
if errorlevel 1 goto :copy_failed

set "VW_RELEASE_TEMP_DIR=%TEMP_DIR%"
set "VW_RELEASE_TEMP_ZIP=%TEMP_ZIP%"
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop'; Compress-Archive -LiteralPath $env:VW_RELEASE_TEMP_DIR -DestinationPath $env:VW_RELEASE_TEMP_ZIP -CompressionLevel Optimal -Force"
if errorlevel 1 goto :zip_failed
if not exist "%TEMP_ZIP%" goto :zip_failed

if exist "%ZIP_PATH%" del /Q "%ZIP_PATH%"
if exist "%ZIP_PATH%" (
  echo Existing zip could not be replaced:
  echo   %ZIP_PATH%
  goto :failed
)

move /Y "%TEMP_ZIP%" "%ZIP_PATH%" >nul
if errorlevel 1 goto :zip_failed

rmdir /S /Q "%TEMP_ROOT%"
echo Created:
echo   %ZIP_PATH%
exit /b 0

:copy_failed
echo Failed to copy a release file.
goto :failed

:zip_failed
echo Failed to create zip:
echo   %ZIP_PATH%
goto :failed

:failed
if exist "%TEMP_ROOT%\" rmdir /S /Q "%TEMP_ROOT%"
exit /b 1
