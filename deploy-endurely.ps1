# Endurely - Azure AI Foundry Deployment
# This script creates everything needed for Endurely with Azure AI Foundry and Managed Identity
# SPDX-License-Identifier: AGPL-3.0-or-later
# Load System.Web for URL encoding
Add-Type -AssemblyName System.Web

Write-Host "🚀 Endurely - Azure AI Foundry Deployment" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Configuration
$RESOURCE_GROUP = "endurely-rg"
$LOCATION = "swedencentral"
$APP_NAME = "endurely-app"
$PLAN_NAME = "endurely-plan"
$AI_HUB_NAME = "endurely-hub"
$AI_PROJECT_NAME = "endurely-project"
$OPENAI_NAME = "endurely-openai"
$DEPLOYMENT_NAME = "gpt-4o-mini"
$MODEL_NAME = "gpt-4o-mini"
$MODEL_VERSION = "2024-07-18"
$SKU = "B1"  # Basic tier for App Service
$DB_SERVER_NAME = "endurely-db-server"
$DB_NAME = "endurelydb"
$DB_ADMIN_USER = "endurely_admin"
$DB_ADMIN_PASSWORD = ""  # Will be generated if empty

Write-Host "📋 Configuration:" -ForegroundColor Yellow
Write-Host "  Resource Group: $RESOURCE_GROUP"
Write-Host "  Location: $LOCATION"
Write-Host "  App Name: $APP_NAME"
Write-Host "  Database Server: $DB_SERVER_NAME"
Write-Host "  Database Name: $DB_NAME"
Write-Host "  AI Hub: $AI_HUB_NAME"
Write-Host "  AI Project: $AI_PROJECT_NAME"
Write-Host "  OpenAI: $OPENAI_NAME"
Write-Host "  Model: $DEPLOYMENT_NAME ($MODEL_NAME)"
Write-Host ""

# Step 1: Create Resource Group
Write-Host "📦 Step 1: Creating resource group..." -ForegroundColor Green
az group create --name $RESOURCE_GROUP --location $LOCATION
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to create resource group" -ForegroundColor Red
    exit 1
}
Write-Host "   ✅ Resource group created" -ForegroundColor Green

# Step 2: Create Azure SQL Database
Write-Host "🗄️  Step 2: Setting up Azure SQL Database..." -ForegroundColor Green

# Check if SQL server exists
$existingDbServer = az sql server show `
    --name $DB_SERVER_NAME `
    --resource-group $RESOURCE_GROUP `
    --query "name" `
    --output tsv 2>$null

if ($existingDbServer) {
    Write-Host "   ✅ Using existing SQL server: $DB_SERVER_NAME" -ForegroundColor Green
} else {
    Write-Host "   Creating Azure SQL Server..." -ForegroundColor Yellow
    Write-Host "   (This may take 2-3 minutes)" -ForegroundColor Gray
    
    # Generate password if not provided
    if (-not $DB_ADMIN_PASSWORD) {
        # Generate a strong password that meets SQL Server requirements
        $randomBytes = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(16)
        $base64String = [Convert]::ToBase64String($randomBytes).Replace("/", "a").Replace("+", "b")
        # Ensure we have enough characters
        if ($base64String.Length -lt 28) {
            $base64String = $base64String + "aBcDeF123456789"
        }
        $DB_ADMIN_PASSWORD = "Pw1!" + $base64String.Substring(0, 28)
    }
    
    # Get current user's object ID for Azure AD admin
    $CURRENT_USER_OID = az ad signed-in-user show --query id --output tsv
    $CURRENT_USER_UPN = az ad signed-in-user show --query userPrincipalName --output tsv
    
    az sql server create `
        --name $DB_SERVER_NAME `
        --resource-group $RESOURCE_GROUP `
        --location $LOCATION `
        --admin-user $DB_ADMIN_USER `
        --admin-password $DB_ADMIN_PASSWORD `
        --enable-ad-only-auth `
        --external-admin-principal-type User `
        --external-admin-name $CURRENT_USER_UPN `
        --external-admin-sid $CURRENT_USER_OID
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to create SQL server" -ForegroundColor Red
        exit 1
    }
    Write-Host "   ✅ SQL server created" -ForegroundColor Green
    
    # Configure firewall to allow Azure services
    Write-Host "   Configuring firewall rules..." -ForegroundColor Yellow
    az sql server firewall-rule create `
        --resource-group $RESOURCE_GROUP `
        --server $DB_SERVER_NAME `
        --name AllowAzureServices `
        --start-ip-address 0.0.0.0 `
        --end-ip-address 0.0.0.0
    
    Write-Host "   ✅ Firewall configured" -ForegroundColor Green
}

# Create database if it doesn't exist
$existingDb = az sql db show `
    --server $DB_SERVER_NAME `
    --resource-group $RESOURCE_GROUP `
    --name $DB_NAME `
    --query "name" `
    --output tsv 2>$null

if (-not $existingDb) {
    Write-Host "   Creating database: $DB_NAME..." -ForegroundColor Yellow
    az sql db create `
        --server $DB_SERVER_NAME `
        --resource-group $RESOURCE_GROUP `
        --name $DB_NAME `
        --service-objective Basic `
        --backup-storage-redundancy Local
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   ✅ Database created" -ForegroundColor Green
    }
} else {
    Write-Host "   ✅ Database already exists: $DB_NAME" -ForegroundColor Green
}

# Get database connection info
$DB_HOST = az sql server show `
    --name $DB_SERVER_NAME `
    --resource-group $RESOURCE_GROUP `
    --query "fullyQualifiedDomainName" `
    --output tsv

Write-Host "   Database host: $DB_HOST" -ForegroundColor Gray

# Step 3: Create or use existing Azure OpenAI resource
Write-Host "🤖 Step 3: Checking for existing Azure OpenAI resource..." -ForegroundColor Green

# Check if OpenAI resource already exists
$existingOpenAI = az cognitiveservices account show `
    --name $OPENAI_NAME `
    --resource-group $RESOURCE_GROUP `
    --query "name" `
    --output tsv 2>$null

if ($existingOpenAI) {
    Write-Host "   ✅ Using existing OpenAI resource: $OPENAI_NAME" -ForegroundColor Green
} else {
    Write-Host "   Creating new Azure OpenAI resource..." -ForegroundColor Yellow
    Write-Host "   (This may take 2-3 minutes)" -ForegroundColor Gray
    az cognitiveservices account create `
        --name $OPENAI_NAME `
        --resource-group $RESOURCE_GROUP `
        --location $LOCATION `
        --kind OpenAI `
        --sku S0 `
        --custom-domain $OPENAI_NAME `
        --assign-identity

    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to create Azure OpenAI resource" -ForegroundColor Red
        Write-Host "Note: Azure OpenAI requires access approval. Visit: https://aka.ms/oai/access" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "   ✅ Azure OpenAI resource created" -ForegroundColor Green
}

# Get the OpenAI endpoint
$OPENAI_ENDPOINT = az cognitiveservices account show `
    --name $OPENAI_NAME `
    --resource-group $RESOURCE_GROUP `
    --query "properties.endpoint" `
    --output tsv

Write-Host "   Endpoint: $OPENAI_ENDPOINT" -ForegroundColor Gray

# Step 4: Deploy the model (or use existing)
Write-Host "🤖 Step 4: Checking for existing model deployment..." -ForegroundColor Green

# Check if deployment exists
$existingDeployment = az cognitiveservices account deployment show `
    --name $OPENAI_NAME `
    --resource-group $RESOURCE_GROUP `
    --deployment-name $DEPLOYMENT_NAME `
    --query "name" `
    --output tsv 2>$null

if ($existingDeployment) {
    Write-Host "   ✅ Using existing deployment: $DEPLOYMENT_NAME" -ForegroundColor Green
} else {
    Write-Host "   Deploying AI model ($MODEL_NAME)..." -ForegroundColor Yellow
    Write-Host "   (This may take 1-2 minutes)" -ForegroundColor Gray

    az cognitiveservices account deployment create `
        --name $OPENAI_NAME `
        --resource-group $RESOURCE_GROUP `
        --deployment-name $DEPLOYMENT_NAME `
        --model-name $MODEL_NAME `
        --model-version $MODEL_VERSION `
        --model-format OpenAI `
        --sku-capacity 10 `
        --sku-name Standard

    if ($LASTEXITCODE -ne 0) {
        Write-Host "⚠️  Model deployment failed. You may need to deploy manually" -ForegroundColor Yellow
    } else {
        Write-Host "   ✅ Model deployed: $DEPLOYMENT_NAME" -ForegroundColor Green
    }
}

# Step 5: Create or use existing AI Hub (Azure AI Foundry)
Write-Host "🏢 Step 5: Checking for existing AI Hub..." -ForegroundColor Green

# Note: AI Hub requires ml extension
az extension add --name ml --upgrade --only-show-errors 2>$null

# First, try to find any existing AI Hub in the resource group
$existingHubName = az ml workspace list `
    --resource-group $RESOURCE_GROUP `
    --query "[?kind=='hub'].name | [0]" `
    --output tsv 2>$null

if ($existingHubName) {
    $AI_HUB_NAME = $existingHubName
    Write-Host "   ✅ Found existing AI Hub: $AI_HUB_NAME" -ForegroundColor Green
} else {
    # Check if the default name exists
    $existingHub = az ml workspace show `
        --name $AI_HUB_NAME `
        --resource-group $RESOURCE_GROUP `
        --query "name" `
        --output tsv 2>$null

    if ($existingHub) {
        Write-Host "   ✅ Using existing AI Hub: $AI_HUB_NAME" -ForegroundColor Green
    } else {
        Write-Host "   Creating AI Hub (Azure AI Foundry)..." -ForegroundColor Yellow
        Write-Host "   (This may take 3-5 minutes)" -ForegroundColor Gray
        
        az ml workspace create `
            --kind hub `
            --name $AI_HUB_NAME `
            --resource-group $RESOURCE_GROUP `
            --location $LOCATION

        if ($LASTEXITCODE -ne 0) {
            Write-Host "⚠️  AI Hub creation failed - continuing without it" -ForegroundColor Yellow
            Write-Host "   You can create it manually in Azure Portal if needed" -ForegroundColor Yellow
        } else {
            Write-Host "   ✅ AI Hub created: $AI_HUB_NAME" -ForegroundColor Green
        }
    }
}

# Step 6: Create or use existing AI Project
if ($existingHubName -or $existingHub -or $LASTEXITCODE -eq 0) {
    Write-Host "📁 Step 6: Checking for existing AI Project..." -ForegroundColor Green
    
    # First, try to find any existing AI Project in the resource group
    $existingProjectName = az ml workspace list `
        --resource-group $RESOURCE_GROUP `
        --query "[?kind=='project'].name | [0]" `
        --output tsv 2>$null
    
    if ($existingProjectName) {
        $AI_PROJECT_NAME = $existingProjectName
        Write-Host "   ✅ Found existing AI Project: $AI_PROJECT_NAME" -ForegroundColor Green
    } else {
        # Check if the default name exists
        $existingProject = az ml workspace show `
            --name $AI_PROJECT_NAME `
            --resource-group $RESOURCE_GROUP `
            --query "name" `
            --output tsv 2>$null
        
        if ($existingProject) {
            Write-Host "   ✅ Using existing AI Project: $AI_PROJECT_NAME" -ForegroundColor Green
        } else {
            Write-Host "   Creating AI Project..." -ForegroundColor Yellow
            az ml workspace create `
                --kind project `
                --name $AI_PROJECT_NAME `
                --resource-group $RESOURCE_GROUP `
                --hub-id "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.MachineLearningServices/workspaces/$AI_HUB_NAME"
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "   ✅ AI Project created: $AI_PROJECT_NAME" -ForegroundColor Green
            }
        }
    }
}

# Step 7: Create App Service Plan
Write-Host "📱 Step 7: Creating App Service Plan..." -ForegroundColor Green
az appservice plan create `
    --name $PLAN_NAME `
    --resource-group $RESOURCE_GROUP `
    --location $LOCATION `
    --is-linux `
    --sku $SKU

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to create App Service Plan" -ForegroundColor Red
    exit 1
}
Write-Host "   ✅ App Service Plan created" -ForegroundColor Green

# Step 8: Create Web App
Write-Host "🌐 Step 8: Creating Web App..." -ForegroundColor Green
az webapp create `
    --name $APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --plan $PLAN_NAME `
    --runtime "PYTHON:3.11"

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to create Web App" -ForegroundColor Red
    exit 1
}
Write-Host "   ✅ Web App created: https://$APP_NAME.azurewebsites.net" -ForegroundColor Green

# Step 9: Enable Managed Identity
Write-Host "🔐 Step 9: Enabling Managed Identity..." -ForegroundColor Green
$PRINCIPAL_ID = az webapp identity assign `
    --name $APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --query principalId `
    --output tsv

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to enable Managed Identity" -ForegroundColor Red
    exit 1
}
Write-Host "   ✅ Managed Identity enabled" -ForegroundColor Green
Write-Host "   Principal ID: $PRINCIPAL_ID" -ForegroundColor Gray

# Step 10: Grant OpenAI access to Managed Identity
Write-Host "🔑 Step 10: Granting OpenAI access..." -ForegroundColor Green
$OPENAI_ID = az cognitiveservices account show `
    --name $OPENAI_NAME `
    --resource-group $RESOURCE_GROUP `
    --query id `
    --output tsv

az role assignment create `
    --role "Cognitive Services OpenAI User" `
    --assignee $PRINCIPAL_ID `
    --scope $OPENAI_ID

if ($LASTEXITCODE -ne 0) {
    Write-Host "⚠️  Role assignment may need time to propagate" -ForegroundColor Yellow
} else {
    Write-Host "   ✅ OpenAI access granted" -ForegroundColor Green
}

# Grant SQL Database access to Managed Identity
Write-Host "   Granting SQL Database access..." -ForegroundColor Yellow

# Get the web app's managed identity name
$APP_IDENTITY_NAME = az webapp show `
    --name $APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --query "identity.principalId" `
    --output tsv

# Add the managed identity as Azure AD admin on SQL Server
az sql server ad-admin create `
    --resource-group $RESOURCE_GROUP `
    --server-name $DB_SERVER_NAME `
    --display-name $APP_NAME `
    --object-id $PRINCIPAL_ID

if ($LASTEXITCODE -eq 0) {
    Write-Host "   ✅ SQL Database access granted to managed identity" -ForegroundColor Green
} else {
    Write-Host "   ⚠️  Could not grant SQL access (may already exist)" -ForegroundColor Yellow
}

# Step 11: Configure App Settings
Write-Host "⚙️  Step 11: Configuring app settings..." -ForegroundColor Green

# Read Entra ID settings from .env if it exists
$ENTRA_TENANT_ID = ""
$ENTRA_CLIENT_ID = ""
$ENTRA_CLIENT_SECRET = ""
$ENTRA_CIAM_DOMAIN = ""
$ENTRA_REDIRECT_URI = ""
$SESSION_SECRET_KEY = ""

if (Test-Path ".env") {
    Get-Content ".env" | ForEach-Object {
        if ($_ -match "^ENTRA_TENANT_ID=(.+)") { $ENTRA_TENANT_ID = $matches[1] }
        if ($_ -match "^ENTRA_CLIENT_ID=(.+)") { $ENTRA_CLIENT_ID = $matches[1] }
        if ($_ -match "^ENTRA_CLIENT_SECRET=(.+)") { $ENTRA_CLIENT_SECRET = $matches[1] }
        if ($_ -match "^ENTRA_CIAM_DOMAIN=(.+)") { $ENTRA_CIAM_DOMAIN = $matches[1] }
        if ($_ -match "^ENTRA_REDIRECT_URI=(.+)") { $ENTRA_REDIRECT_URI = $matches[1] }
        if ($_ -match "^SESSION_SECRET_KEY=(.+)") { $SESSION_SECRET_KEY = $matches[1] }
    }
}

# Generate SESSION_SECRET_KEY if not provided
if (-not $SESSION_SECRET_KEY) {
    Write-Host "   Generating SESSION_SECRET_KEY..." -ForegroundColor Yellow
    $SESSION_SECRET_KEY = [Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
}

# Set ENTRA_REDIRECT_URI if not provided
if (-not $ENTRA_REDIRECT_URI) {
    $ENTRA_REDIRECT_URI = "https://$APP_NAME.azurewebsites.net/auth/callback"
}

# Build DATABASE_URL with Managed Identity authentication using ODBC connection string format
# Use odbc_connect parameter to pass the full connection string to avoid parsing issues
$odbcString = "Driver={ODBC Driver 18 for SQL Server};Server=${DB_HOST},1433;Database=${DB_NAME};Authentication=ActiveDirectoryMsi;Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30"
$encodedOdbcString = [System.Web.HttpUtility]::UrlEncode($odbcString)
$DATABASE_URL = "mssql+pyodbc:///?odbc_connect=$encodedOdbcString"
Write-Host "   Database connection configured (using Managed Identity)" -ForegroundColor Gray

# Build settings JSON
$settings = @{
    "LLM_PROVIDER" = "azure_ai"
    # Use AZURE_AI_* variables (required by the application)
    # v1 API: No longer requires api_version parameter!
    "AZURE_AI_ENDPOINT" = $OPENAI_ENDPOINT
    "AZURE_AI_DEPLOYMENT_NAME" = $DEPLOYMENT_NAME
    "AZURE_AI_AUTH" = "entra_id"
    # Legacy AZURE_OPENAI_* for backward compatibility (optional)
    "AZURE_OPENAI_ENDPOINT" = $OPENAI_ENDPOINT
    "AZURE_OPENAI_DEPLOYMENT" = $DEPLOYMENT_NAME
    "AZURE_OPENAI_AUTH_MODE" = "entra_id"
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"
    "ENABLE_AUTH" = "true"
    "SESSION_SECRET_KEY" = $SESSION_SECRET_KEY
    "ENTRA_REDIRECT_URI" = $ENTRA_REDIRECT_URI
    "DATABASE_URL" = $DATABASE_URL
}

# Add Entra settings if available
if ($ENTRA_TENANT_ID) { $settings["ENTRA_TENANT_ID"] = $ENTRA_TENANT_ID }
if ($ENTRA_CLIENT_ID) { $settings["ENTRA_CLIENT_ID"] = $ENTRA_CLIENT_ID }
if ($ENTRA_CLIENT_SECRET) { $settings["ENTRA_CLIENT_SECRET"] = $ENTRA_CLIENT_SECRET }
if ($ENTRA_CIAM_DOMAIN) { $settings["ENTRA_CIAM_DOMAIN"] = $ENTRA_CIAM_DOMAIN }

# Convert to space-separated format
$settingsArgs = @()
foreach ($key in $settings.Keys) {
    $settingsArgs += "$key=`"$($settings[$key])`""
}

az webapp config appsettings set `
    --name $APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --settings $settingsArgs

if ($LASTEXITCODE -ne 0) {
    Write-Host "⚠️  Failed to set some app settings" -ForegroundColor Yellow
} else {
    Write-Host "   ✅ App settings configured" -ForegroundColor Green
}

# Step 12: Deploy the application
Write-Host "📦 Step 12: Deploying application code..." -ForegroundColor Green

# Create deployment package
if (Test-Path "deploy_package.zip") {
    Remove-Item "deploy_package.zip" -Force
}
Compress-Archive -Path app,requirements.txt,startup.sh,Dockerfile -DestinationPath deploy_package.zip -Force

# Deploy
az webapp deployment source config-zip `
    --resource-group $RESOURCE_GROUP `
    --name $APP_NAME `
    --src deploy_package.zip

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Deployment failed" -ForegroundColor Red
    exit 1
}
Write-Host "   ✅ Application deployed" -ForegroundColor Green

# Clean up
Remove-Item "deploy_package.zip" -Force

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "✅ Deployment Complete!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "📍 Your Endurely app:" -ForegroundColor Yellow
Write-Host "   https://$APP_NAME.azurewebsites.net" -ForegroundColor Cyan
Write-Host ""
Write-Host "🔧 Resources created:" -ForegroundColor Yellow
Write-Host "   Resource Group: $RESOURCE_GROUP"
Write-Host "   Web App: $APP_NAME"
Write-Host "   Database Server: $DB_SERVER_NAME"
Write-Host "   Database: $DB_NAME"
Write-Host "   AI Hub: $AI_HUB_NAME"
Write-Host "   AI Project: $AI_PROJECT_NAME"
Write-Host "   OpenAI: $OPENAI_NAME"
Write-Host "   Model Deployment: $DEPLOYMENT_NAME"
Write-Host ""
Write-Host "🗄️  Database:" -ForegroundColor Yellow
Write-Host "   ✅ Azure SQL Database configured with Managed Identity" -ForegroundColor Green
Write-Host "   Host: $DB_HOST"
Write-Host "   Database: $DB_NAME"
Write-Host ""
Write-Host "🔐 Authentication:" -ForegroundColor Yellow
if ($ENTRA_TENANT_ID) {
    Write-Host "   ✅ Entra External ID configured" -ForegroundColor Green
    Write-Host "   Redirect URI: $ENTRA_REDIRECT_URI"
    Write-Host "   Update your app registration to include this redirect URI"
} else {
    Write-Host "   ⚠️  Entra External ID not configured" -ForegroundColor Yellow
    Write-Host "   Follow ENTRA_EXTERNAL_ID_SETUP.md to set up authentication"
    Write-Host "   Then update app settings with:"
    Write-Host "      ENTRA_TENANT_ID, ENTRA_CLIENT_ID, ENTRA_CLIENT_SECRET, ENTRA_CIAM_DOMAIN"
}
Write-Host ""
Write-Host "🔑 Session Secret:" -ForegroundColor Yellow
Write-Host "   SESSION_SECRET_KEY: Generated and configured"
Write-Host ""
Write-Host "⏱️  Note: App may take 2-3 minutes to fully start" -ForegroundColor Gray
Write-Host ""
