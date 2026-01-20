@echo off
echo ================================================
echo Endurely - Setup Script
echo ================================================
echo.

echo Step 1: Creating virtual environment...
python -m venv venv
if errorlevel 1 (
    echo ERROR: Failed to create virtual environment
    pause
    exit /b 1
)
echo ✓ Virtual environment created
echo.

echo Step 2: Activating virtual environment...
call venv\Scripts\activate.bat
echo ✓ Virtual environment activated
echo.

echo Step 3: Installing dependencies...
pip install -r requirements.txt
if errorlevel 1 (
    echo ERROR: Failed to install dependencies
    pause
    exit /b 1
)
echo ✓ Dependencies installed
echo.

echo Step 4: Checking for .env file...
if not exist .env (
    echo Creating .env file from .env.example...
    copy .env.example .env
    echo.
    echo ================================================
    echo IMPORTANT: Configure Azure OpenAI
    echo ================================================
    echo Please edit the .env file and add your Azure OpenAI configuration:
    echo - AZURE_AI_ENDPOINT
    echo - AZURE_AI_DEPLOYMENT_NAME
    echo - AZURE_AI_AUTH (entra_id or api_key)
    echo.
    pause
) else (
    echo ✓ .env file already exists
    echo.
    echo Running setup test...
    python test_setup.py
)

echo.
echo Setup complete!
echo.
echo Next steps:
echo 1. Edit .env file with your Azure OpenAI configuration
echo 2. Run the web app: python app/main.py
echo 3. Access at: http://localhost:8000
echo.
pause
