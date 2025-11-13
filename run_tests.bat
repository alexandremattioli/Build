@echo off
REM Test runner for Build Infrastructure
REM Automatically finds Python and runs tests

echo Looking for Python installation...

where python >nul 2>&1
if %errorlevel% equ 0 (
    echo Found Python
    python --version
    echo.
    echo Running tests...
    python run_tests.py
    exit /b %errorlevel%
)

where py >nul 2>&1
if %errorlevel% equ 0 (
    echo Found Python via py launcher
    py --version
    echo.
    echo Running tests...
    py run_tests.py
    exit /b %errorlevel%
)

echo ERROR: Python not found in PATH
echo Please install Python 3.8+ from python.org or the Microsoft Store
echo Then run this script again
exit /b 1
