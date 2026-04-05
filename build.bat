@echo off
setlocal enabledelayedexpansion

echo ============================================
echo Glimpse Build Script
echo ============================================

:: Change to script directory
cd /d "%~dp0"

call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
if errorlevel 1 (
    echo ERROR: Failed to set RAD Studio environment
    exit /b 1
)

:: ============================================
:: WLX Plugin (Win64 Debug)
:: ============================================
echo.
echo [1/2] Building WLX plugin (Win64 Debug)...

msbuild wlx\Glimpse.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /v:m /nologo
if errorlevel 1 (
    echo ERROR: WLX build failed
    exit /b 1
)

echo WLX build successful.

:: ============================================
:: WCX Plugin (Win64 Debug)
:: ============================================
echo.
echo [2/2] Building WCX plugin (Win64 Debug)...

msbuild wcx\Glimpse.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /v:m /nologo
if errorlevel 1 (
    echo ERROR: WCX build failed
    exit /b 1
)

echo WCX build successful.

echo.
echo ============================================
echo All builds successful.
echo ============================================

endlocal
