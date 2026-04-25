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

REM Compile WLX icon resources. Delphi 12's cgrc 1.2.3 cannot find rc.exe
REM via PATH; Delphi 11.3's cgrc 1.2.2 ships rc.exe co-located, so we use
REM that. Adjust the path if Delphi 11.3 is not installed.
set "CGRC=C:\Program Files (x86)\Embarcadero\Studio\22.0\bin\cgrc.exe"
REM In-block echo cannot expand %CGRC% because the (x86) parens would
REM prematurely close the IF block.
if not exist "%CGRC%" (
    echo ERROR: cgrc.exe not found. Edit test.bat to point CGRC at a Delphi
    echo        installation whose bin folder has both cgrc.exe and rc.exe.
    pause
    exit /b 1
)
"%CGRC%" -c65001 wlx\icons.rc -fowlx\icons.res
if errorlevel 1 (
    echo ERROR: Failed to compile wlx\icons.rc
    pause
    exit /b 1
)

if not exist "tests\GlimpseTests.dproj" (
    echo ERROR: Test project not found at tests\GlimpseTests.dproj
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
