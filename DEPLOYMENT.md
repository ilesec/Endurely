# Azure App Services Deployment Guide

## Prerequisites

1. **Azure CLI** - Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli
2. **Azure Account** - Sign up at: https://azure.microsoft.com/free/
3. **Azure OpenAI Resource** - Create in Azure Portal with GPT-4 or GPT-3.5 deployment

## Quick Deploy (Recommended)

### Option 1: Using Azure CLI

```bash
# Login to Azure
az login

# Create a resource group
az group create --name triathlon-rg --location swedencentral

# Create an App Service plan (B1 tier)
az appservice plan create --name triathlon-plan --resource-group triathlon-rg --sku B1 --is-linux

# Create the web app
az webapp create --resource-group triathlon-rg --plan triathlon-plan --name triathlon-program-generator --runtime "PYTHON:3.11"

# Configure startup command (IMPORTANT: This must be set before deploying)
az webapp config set --resource-group triathlon-rg --name triathlon-program-generator --startup-file "startup.sh"

# Set environment variables (Replace with your actual Azure OpenAI details)
az webapp config appsettings set --resource-group triathlon-rg --name triathlon-program-generator --settings \
  LLM_PROVIDER="azure_ai" \
  AZURE_AI_ENDPOINT="https://your-resource.openai.azure.com/" \
  AZURE_AI_DEPLOYMENT_NAME="gpt-4" \
  AZURE_AI_AUTH="entra_id" \
  DATABASE_URL="sqlite:///./workouts.db" \
  SCM_DO_BUILD_DURING_DEPLOYMENT="true"

# Enable logging
az webapp log config --resource-group triathlon-rg --name triathlon-program-generator \
  --application-logging filesystem --detailed-error-messages true --web-server-logging filesystem

# Deploy your code using ZIP deploy (most reliable)
cd "c:\Users\ilkkahyvonen\Personal projects\triathlon-program-generator"
az webapp deployment source config-zip --resource-group triathlon-rg --name triathlon-program-generator --src deployment.zip
```

Your app will be available at: `https://triathlon-program-generator.azurewebsites.net`

### Option 2: Using VS Code Extension

1. Install the **Azure App Service** extension in VS Code
2. Click the Azure icon in the sidebar
3. Sign in to Azure
4. Right-click on "App Services" → "Create New Web App"
5. Follow the prompts:
   - Name: `triathlon-program-generator`
   - Runtime: `Python 3.11`
   - Pricing tier: `B1` (Basic)
6. Right-click your new app → "Deploy to Web App"
7. Select your project folder
8. Configure environment variables in Azure Portal

### Option 3: GitHub Actions (CI/CD)

1. In Azure Portal, go to your App Service
2. Navigate to "Deployment Center"
3. Select "GitHub" as source
4. Authorize and select your repository
5. Choose "GitHub Actions" as build provider
6. Azure will create a workflow file automatically

## Configuration

### Required Environment Variables

Set these in Azure Portal → Configuration → Application Settings:

| Variable | Value | Description |
|----------|-------|-------------|
| `LLM_PROVIDER` | `azure_ai` | Use Azure OpenAI |
| `AZURE_AI_ENDPOINT` | `https://your-resource.openai.azure.com/` | Your Azure OpenAI endpoint |
| `AZURE_AI_DEPLOYMENT_NAME` | `gpt-4` or `gpt-35-turbo` | Your model deployment name |
| `AZURE_AI_AUTH` | `entra_id` | Use managed identity (or `api_key`) |
| `DATABASE_URL` | `sqlite:///./workouts.db` | Database connection string |
| `SCM_DO_BUILD_DURING_DEPLOYMENT` | `true` | Enable build during deployment |

### Startup Command

In Azure Portal → Configuration → General Settings:

```bash
startup.sh
```

Or use Gunicorn directly:
```bash
gunicorn app.main:app --workers 4 --worker-class uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000
```

## Database Options

### Option 1: SQLite (Current - Good for testing)
- Simple, no extra setup needed
- **Note**: On Azure App Service, the file system is ephemeral. Data may be lost on restart.

### Option 2: Azure SQL Database (Production)
```bash
# Create Azure SQL Database
az sql server create --name triathlon-sql --resource-group triathlon-rg --location eastus --admin-user sqladmin --admin-password YourPassword123!

az sql db create --resource-group triathlon-rg --server triathlon-sql --name triathlon-db --service-objective S0

# Update DATABASE_URL
DATABASE_URL=mssql+pyodbc://sqladmin:YourPassword123!@triathlon-sql.database.windows.net/triathlon-db?driver=ODBC+Driver+17+for+SQL+Server
```

Add to `azure-requirements.txt`:
```
pyodbc
```

### Option 3: PostgreSQL (Recommended for Production)
```bash
# Create Azure Database for PostgreSQL
az postgres flexible-server create --name triathlon-postgres --resource-group triathlon-rg --location eastus --admin-user adminuser --admin-password YourPassword123! --sku-name Standard_B1ms --storage-size 32

# Update DATABASE_URL
DATABASE_URL=postgresql://adminuser:YourPassword123!@triathlon-postgres.postgres.database.azure.com/postgres
```

Add to `azure-requirements.txt`:
```
psycopg2-binary
```

## Verify Deployment

1. Check logs:
```bash
az webapp log tail --resource-group triathlon-rg --name triathlon-program-generator
```

2. Test the application:
```bash
curl https://triathlon-program-generator.azurewebsites.net
```

3. View in browser:
```
https://triathlon-program-generator.azurewebsites.net
```

## Troubleshooting

### App won't start
- Check logs: `az webapp log tail`
- Verify startup command in Configuration
- Ensure all dependencies are in `azure-requirements.txt`

### Database errors
- SQLite: Works but data is ephemeral
- For production: Use Azure SQL or PostgreSQL
- Check DATABASE_URL format

### API errors
- Verify Azure OpenAI endpoint and deployment name are correct
- Check that managed identity has "Cognitive Services OpenAI User" role
- Test Azure OpenAI connection using Azure Portal or Azure CLI
- If using API key auth, verify AZURE_AI_API_KEY is set

### Performance issues
- Scale up: `az appservice plan update --sku S1`
- Increase workers in startup command
- Monitor metrics in Azure Portal

## Cost Optimization

**Free/Low-Cost Options:**
- **F1 (Free)**: Good for testing, limited to 60 minutes/day
- **B1 (Basic)**: ~$13/month, good for small apps
- **S1 (Standard)**: ~$70/month, includes auto-scaling

**Stop/Start app to save costs:**
```bash
az webapp stop --resource-group triathlon-rg --name triathlon-program-generator
az webapp start --resource-group triathlon-rg --name triathlon-program-generator
```

## Clean Up Resources

To delete everything:
```bash
az group delete --name triathlon-rg --yes --no-wait
```

## Next Steps

1. Set up custom domain (optional)
2. Enable HTTPS (automatic with Azure)
3. Configure auto-scaling
4. Set up Application Insights for monitoring
5. Implement Redis cache for better performance

## Support

- Azure Documentation: https://docs.microsoft.com/azure/app-service/
- FastAPI on Azure: https://docs.microsoft.com/azure/app-service/quickstart-python
