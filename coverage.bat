@echo off
setlocal

echo ============================================
echo Glimpse Code Coverage Report
echo ============================================

:: Change to script directory
cd /d "%~dp0"

:: ============================================
:: Step 1: Compile Tests with MAP file
:: ============================================
echo.
echo [1/4] Compiling tests with MAP file...

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

:: Build with detailed MAP file (DCC_MapFile=3)
msbuild tests\GlimpseTests.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /p:DCC_MapFile=3 /v:m /nologo
if errorlevel 1 (
    echo.
    echo ERROR: Test build failed
    pause
    exit /b 1
)

echo Build successful.

:: Check MAP file exists
if not exist "tests\Win64\Debug\GlimpseTests.map" (
    echo ERROR: MAP file not generated. Check project linker settings.
    pause
    exit /b 1
)

:: ============================================
:: Step 2: Generate Unit List
:: ============================================
echo.
echo [2/4] Generating unit list from source files...

:: Generate list of all unit names from src directory
if exist "coverage\units.lst" del "coverage\units.lst"
if exist "coverage\srcpaths.lst" del "coverage\srcpaths.lst"
if not exist "coverage" mkdir coverage

:: Scan src directory for .pas files
for %%f in (src\*.pas) do echo %%~nxf>> coverage\units.lst

:: Source paths (absolute)
echo %~dp0src>> coverage\srcpaths.lst

:: ============================================
:: Step 3: Run Code Coverage
:: ============================================
echo.
echo [3/4] Running tests with code coverage...
echo.

:: Run CodeCoverage with source path file and unit file
coverage\Win64\CodeCoverage.exe ^
    -e "tests\Win64\Debug\GlimpseTests.exe" ^
    -m "tests\Win64\Debug\GlimpseTests.map" ^
    -spf coverage\srcpaths.lst ^
    -uf coverage\units.lst ^
    -od coverage ^
    -html

set COVERAGE_RESULT=%errorlevel%

if %COVERAGE_RESULT% neq 0 (
    echo.
    echo WARNING: Coverage tool exited with code %COVERAGE_RESULT%
)

:: ============================================
:: Step 4: Show Results
:: ============================================
echo.
echo [4/4] Coverage report generated.
echo.

if exist "coverage\CodeCoverage_summary.html" (
    echo ============================================
    echo Report: coverage\CodeCoverage_summary.html
    echo ============================================
    echo.
    echo Opening report in browser...
    start "" "coverage\CodeCoverage_summary.html"
) else (
    echo Report files are in: coverage\
    dir /b coverage\*.html 2>nul
)

endlocal
