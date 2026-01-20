#!/bin/bash

# Startup script for Azure App Services
echo "Starting Endurely..."

# Create database if it doesn't exist
python -c "from app.database import init_db; init_db()"

# Get PORT from Azure environment variable (defaults to 8000)
PORT="${PORT:-8000}"

# Start the application with gunicorn
# - Use a longer timeout for LLM calls
# - Use a single worker to reduce memory pressure on smaller App Service plans
gunicorn app.main:app --workers 1 --worker-class uvicorn.workers.UvicornWorker --bind 0.0.0.0:$PORT --timeout 600 --access-logfile - --error-logfile -
