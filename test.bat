@echo off
setlocal

echo ============================================
echo Glimpse Test Runner
echo ============================================

:: Change to script directory
cd /d "%~dp0"

:: ============================================
:: Step 1: Compile Tests
:: ============================================
echo.
echo [1/2] Compiling tests...

call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
if errorlevel 1 (
    echo ERROR: Failed to set RAD Studio environment
    pause
    exit /b 1
)

if not exist "tests\GlimpseTests.dproj" (
    echo ERROR: Test project not found at tests\GlimpseTests.dproj
    echo        Create the test project first.
    pause
    exit /b 1
)

msbuild tests\GlimpseTests.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /v:m /nologo
if errorlevel 1 (
    echo.
    echo ERROR: Test build failed
    pause
    exit /b 1
)

echo Build successful.

:: ============================================
:: Step 2: Run Tests
:: ============================================
echo.
echo [2/2] Running tests...
echo.

tests\Win64\Debug\GlimpseTests.exe
set TEST_RESULT=%errorlevel%

echo.
if %TEST_RESULT% neq 0 (
    echo ============================================
    echo TESTS FAILED with exit code %TEST_RESULT%
    echo ============================================
    pause
    exit /b %TEST_RESULT%
)

echo ============================================
echo ALL TESTS PASSED
echo ============================================

endlocal
