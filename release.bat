@echo off
setlocal enabledelayedexpansion

echo ============================================
echo Glimpse Release Build Script
echo ============================================

:: Change to script directory
cd /d "%~dp0"

:: ============================================
:: Step 1: Set up build environment
:: ============================================
echo.
echo [1/6] Setting up build environment...

call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
if errorlevel 1 (
    echo ERROR: Failed to set RAD Studio environment
    exit /b 1
)

:: ============================================
:: Step 2: Build WLX plugin (Win32 + Win64)
:: ============================================
echo.
echo [2/6] Building WLX plugin...

echo   Win32 Release...
msbuild wlx\Glimpse.dproj /t:Build /p:Config=Release /p:Platform=Win32 /v:m /nologo
if errorlevel 1 (
    echo ERROR: WLX Win32 build failed
    exit /b 1
)

echo   Win64 Release...
msbuild wlx\Glimpse.dproj /t:Build /p:Config=Release /p:Platform=Win64 /v:m /nologo
if errorlevel 1 (
    echo ERROR: WLX Win64 build failed
    exit /b 1
)

echo WLX builds successful.

:: ============================================
:: Step 3: Build WCX plugin (Win32 + Win64)
:: ============================================
echo.
echo [3/6] Building WCX plugin...

echo   Win32 Release...
msbuild wcx\Glimpse.dproj /t:Build /p:Config=Release /p:Platform=Win32 /v:m /nologo
if errorlevel 1 (
    echo ERROR: WCX Win32 build failed
    exit /b 1
)

echo   Win64 Release...
msbuild wcx\Glimpse.dproj /t:Build /p:Config=Release /p:Platform=Win64 /v:m /nologo
if errorlevel 1 (
    echo ERROR: WCX Win64 build failed
    exit /b 1
)

echo WCX builds successful.

:: ============================================
:: Step 4: Get git branch and tag
:: ============================================
echo.
echo [4/6] Getting git info...

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
set BASE_NAME=glimpse_%BRANCH%
if not "%TAG%"=="" set BASE_NAME=glimpse_%BRANCH%_%TAG%

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
echo Archives: %BASE_NAME%_wlx.zip, %BASE_NAME%_wcx.zip

:: ============================================
:: Step 5: Create WLX archive
:: ============================================
echo.
echo [5/6] Creating WLX archive...

if exist "%BASE_NAME%_wlx.zip" del "%BASE_NAME%_wlx.zip"

powershell -NoProfile -Command ^
    "$staging = 'build_temp_wlx'; " ^
    "$archive = '%BASE_NAME%_wlx.zip'; " ^
    "$version = '%VERSION%'; " ^
    "if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }; " ^
    "New-Item -ItemType Directory -Path $staging | Out-Null; " ^
    "$filesToCopy = @(" ^
        "@{Src='wlx\Win32\Release\Glimpse.wlx';    Dst=\"$staging\Glimpse.wlx\"}, " ^
        "@{Src='wlx\Win64\Release\Glimpse.wlx64';  Dst=\"$staging\Glimpse.wlx64\"}, " ^
        "@{Src='README.md';                            Dst=\"$staging\README.md\"}, " ^
        "@{Src='LICENSE';                              Dst=\"$staging\LICENSE\"}" ^
    "); " ^
    "$optionalFiles = @(" ^
        "@{Src='Glimpse.ini'; Dst=\"$staging\Glimpse.ini\"}" ^
    "); " ^
    "$missing = $filesToCopy | Where-Object { -not (Test-Path $_.Src) } | ForEach-Object { $_.Src }; " ^
    "if ($missing) { Write-Host 'ERROR: Missing files:' $missing -ForegroundColor Red; exit 1 }; " ^
    "$filesToCopy | ForEach-Object { Copy-Item $_.Src $_.Dst }; " ^
    "$optionalFiles | Where-Object { Test-Path $_.Src } | ForEach-Object { Copy-Item $_.Src $_.Dst }; " ^
    "$inf = @('[plugininstall]', " ^
        "'description=Video frame preview - extract and display evenly-spaced frames (32bit+64bit)', " ^
        "'type=wlx', " ^
        "'file=Glimpse.wlx', " ^
        "'file64=Glimpse.wlx64', " ^
        "'defaultdir=Glimpse', " ^
        "\"version=$version\", " ^
        "'defaultextension=mp4'" ^
    "); " ^
    "$inf | Out-File -FilePath \"$staging\pluginst.inf\" -Encoding ASCII; " ^
    "if (Test-Path $archive) { Remove-Item $archive -Force }; " ^
    "Compress-Archive -Path \"$staging\*\" -DestinationPath $archive; " ^
    "Remove-Item $staging -Recurse -Force; " ^
    "if ($?) { Write-Host 'WLX archive created.' } else { exit 1 }"

if errorlevel 1 (
    echo ERROR: Failed to create WLX archive
    exit /b 1
)

:: ============================================
:: Step 6: Create WCX archive
:: ============================================
echo.
echo [6/6] Creating WCX archive...

if exist "%BASE_NAME%_wcx.zip" del "%BASE_NAME%_wcx.zip"

powershell -NoProfile -Command ^
    "$staging = 'build_temp_wcx'; " ^
    "$archive = '%BASE_NAME%_wcx.zip'; " ^
    "$version = '%VERSION%'; " ^
    "if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }; " ^
    "New-Item -ItemType Directory -Path $staging | Out-Null; " ^
    "$filesToCopy = @(" ^
        "@{Src='wcx\Win32\Release\Glimpse.wcx';    Dst=\"$staging\Glimpse.wcx\"}, " ^
        "@{Src='wcx\Win64\Release\Glimpse.wcx64';  Dst=\"$staging\Glimpse.wcx64\"}, " ^
        "@{Src='wcx\config.bat';                       Dst=\"$staging\config.bat\"}, " ^
        "@{Src='README.md';                            Dst=\"$staging\README.md\"}, " ^
        "@{Src='LICENSE';                              Dst=\"$staging\LICENSE\"}" ^
    "); " ^
    "$missing = $filesToCopy | Where-Object { -not (Test-Path $_.Src) } | ForEach-Object { $_.Src }; " ^
    "if ($missing) { Write-Host 'ERROR: Missing files:' $missing -ForegroundColor Red; exit 1 }; " ^
    "$filesToCopy | ForEach-Object { Copy-Item $_.Src $_.Dst }; " ^
    "$inf = @('[plugininstall]', " ^
        "'description=Video frame extractor - extract evenly-spaced frames as image files (32bit+64bit)', " ^
        "'type=wcx', " ^
        "'file=Glimpse.wcx', " ^
        "'file64=Glimpse.wcx64', " ^
        "'defaultdir=Glimpse', " ^
        "\"version=$version\", " ^
        "'defaultextension=mp4'" ^
    "); " ^
    "$inf | Out-File -FilePath \"$staging\pluginst.inf\" -Encoding ASCII; " ^
    "if (Test-Path $archive) { Remove-Item $archive -Force }; " ^
    "Compress-Archive -Path \"$staging\*\" -DestinationPath $archive; " ^
    "Remove-Item $staging -Recurse -Force; " ^
    "if ($?) { Write-Host 'WCX archive created.' } else { exit 1 }"

if errorlevel 1 (
    echo ERROR: Failed to create WCX archive
    exit /b 1
)

:: ============================================
:: Summary
:: ============================================
echo.
echo ============================================
echo Release build complete:
echo   WLX: %BASE_NAME%_wlx.zip
echo   WCX: %BASE_NAME%_wcx.zip
echo ============================================

endlocal
