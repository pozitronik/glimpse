@echo off
setlocal enabledelayedexpansion

echo ============================================
echo VideoThumb Release Build Script
echo ============================================

:: Change to script directory
cd /d "%~dp0"

:: ============================================
:: Step 1: Set up build environment
:: ============================================
echo.
echo [1/5] Setting up build environment...

call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
if errorlevel 1 (
    echo ERROR: Failed to set RAD Studio environment
    exit /b 1
)

:: ============================================
:: Step 2: Build WLX plugin (Win32 + Win64)
:: ============================================
echo.
echo [2/5] Building VideoThumb plugin...

echo   Win32 Release...
msbuild src\VideoThumb.dproj /t:Build /p:Config=Release /p:Platform=Win32 /v:m /nologo
if errorlevel 1 (
    echo ERROR: Win32 build failed
    exit /b 1
)

echo   Win64 Release...
msbuild src\VideoThumb.dproj /t:Build /p:Config=Release /p:Platform=Win64 /v:m /nologo
if errorlevel 1 (
    echo ERROR: Win64 build failed
    exit /b 1
)

echo Plugin builds successful.

:: ============================================
:: Step 3: Get git branch and tag
:: ============================================
echo.
echo [3/5] Getting git info...

:: Get current branch name
for /f "tokens=*" %%i in ('git rev-parse --abbrev-ref HEAD 2^>nul') do set BRANCH=%%i

:: If detached HEAD, use short commit hash
if "%BRANCH%"=="HEAD" (
    for /f "tokens=*" %%i in ('git rev-parse --short HEAD 2^>nul') do set BRANCH=%%i
)

:: If still empty, use "unknown"
if "%BRANCH%"=="" set BRANCH=unknown

:: Get current tag (if HEAD is tagged)
set TAG=
for /f "tokens=*" %%i in ('git describe --tags --exact-match HEAD 2^>nul') do set TAG=%%i

:: Build archive base name
set BASE_NAME=videothumb_%BRANCH%
if not "%TAG%"=="" set BASE_NAME=videothumb_%BRANCH%_%TAG%

:: Replace invalid filename characters (/ -> -)
set BASE_NAME=%BASE_NAME:/=-%

:: Version string for pluginst.inf (tag or "dev")
set VERSION=%TAG%
if "%VERSION%"=="" set VERSION=dev

echo Branch: %BRANCH%
if not "%TAG%"=="" (
    echo Tag: %TAG%
) else (
    echo Tag: ^(none^)
)
echo Archive: %BASE_NAME%.zip

:: ============================================
:: Step 4: Create ZIP archive
:: ============================================
echo.
echo [4/5] Creating archive...

if exist "%BASE_NAME%.zip" del "%BASE_NAME%.zip"

powershell -NoProfile -Command ^
    "$staging = 'build_temp'; " ^
    "$archive = '%BASE_NAME%.zip'; " ^
    "$version = '%VERSION%'; " ^
    "if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }; " ^
    "New-Item -ItemType Directory -Path $staging | Out-Null; " ^
    "$filesToCopy = @(" ^
        "@{Src='src\Win32\Release\VideoThumb.wlx';   Dst=\"$staging\VideoThumb.wlx\"}, " ^
        "@{Src='src\Win64\Release\VideoThumb.wlx64';  Dst=\"$staging\VideoThumb.wlx64\"}, " ^
        "@{Src='README.md';                            Dst=\"$staging\README.md\"}, " ^
        "@{Src='LICENSE';                              Dst=\"$staging\LICENSE\"}" ^
    "); " ^
    "$optionalFiles = @(" ^
        "@{Src='VideoThumb.ini'; Dst=\"$staging\VideoThumb.ini\"}" ^
    "); " ^
    "$missing = $filesToCopy | Where-Object { -not (Test-Path $_.Src) } | ForEach-Object { $_.Src }; " ^
    "if ($missing) { Write-Host 'ERROR: Missing files:' $missing -ForegroundColor Red; exit 1 }; " ^
    "$filesToCopy | ForEach-Object { Copy-Item $_.Src $_.Dst }; " ^
    "$optionalFiles | Where-Object { Test-Path $_.Src } | ForEach-Object { Copy-Item $_.Src $_.Dst }; " ^
    "$inf = @('[plugininstall]', " ^
        "'description=Video frame preview - extract and display evenly-spaced frames (32bit+64bit)', " ^
        "'type=wlx', " ^
        "'file=VideoThumb.wlx', " ^
        "'defaultdir=VideoThumb', " ^
        "\"version=$version\", " ^
        "'defaultextension=mp4'" ^
    "); " ^
    "$inf | Out-File -FilePath \"$staging\pluginst.inf\" -Encoding ASCII; " ^
    "if (Test-Path $archive) { Remove-Item $archive -Force }; " ^
    "Compress-Archive -Path \"$staging\*\" -DestinationPath $archive; " ^
    "Remove-Item $staging -Recurse -Force; " ^
    "if ($?) { Write-Host 'Archive created successfully.' } else { exit 1 }"

if errorlevel 1 (
    echo ERROR: Failed to create archive
    exit /b 1
)

:: ============================================
:: Step 5: Summary
:: ============================================
echo.
echo ============================================
echo Release build complete:
echo   Archive: %BASE_NAME%.zip
echo ============================================

endlocal
