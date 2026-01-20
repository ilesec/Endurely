# Endurely - Azure AI Foundry Deployment
# This script creates everything needed for Endurely with Azure AI Foundry and Managed Identity

Write-Host "🚀 Endurely - Azure AI Foundry Deployment" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Configuration
$RESOURCE_GROUP = "endurely-rg"
$LOCATION = "swedencentral"
$APP_NAME = "endurely-app"
$PLAN_NAME = "endurely-plan"
$AI_HUB_NAME = "endurely-hub-$(Get-Random -Minimum 1000 -Maximum 9999)"
$AI_PROJECT_NAME = "endurely-project"
$OPENAI_NAME = "endurely-openai-$(Get-Random -Minimum 1000 -Maximum 9999)"
$DEPLOYMENT_NAME = "gpt-4o-mini"
$MODEL_NAME = "gpt-4o-mini"
$MODEL_VERSION = "2024-07-18"
$SKU = "B1"  # Basic tier for App Service

Write-Host "📋 Configuration:" -ForegroundColor Yellow
Write-Host "  Resource Group: $RESOURCE_GROUP"
Write-Host "  Location: $LOCATION"
Write-Host "  App Name: $APP_NAME"
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

# Step 2: Create or use existing Azure OpenAI resource
Write-Host "🤖 Step 2: Checking for existing Azure OpenAI resource..." -ForegroundColor Green

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

# Step 3: Deploy the model (or use existing)
Write-Host "🤖 Step 3: Checking for existing model deployment..." -ForegroundColor Green

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

# Step 4: Create or use existing AI Hub (Azure AI Foundry)
Write-Host "🏢 Step 4: Checking for existing AI Hub..." -ForegroundColor Green

# Note: AI Hub requires ml extension
az extension add --name ml --upgrade --only-show-errors 2>$null

# Check if AI Hub exists
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

# Step 5: Create or use existing AI Project
if ($existingHub -or $LASTEXITCODE -eq 0) {
    Write-Host "📁 Step 5: Checking for existing AI Project..." -ForegroundColor Green
    
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

# Step 6: Create App Service Plan
Write-Host "📱 Step 6: Creating App Service Plan..." -ForegroundColor Green
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

# Step 7: Create Web App
Write-Host "🌐 Step 7: Creating Web App..." -ForegroundColor Green
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

# Step 8: Enable Managed Identity
Write-Host "🔐 Step 8: Enabling Managed Identity..." -ForegroundColor Green
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

# Step 9: Grant OpenAI access to Managed Identity
Write-Host "🔑 Step 9: Granting OpenAI access..." -ForegroundColor Green
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

# Step 10: Configure App Settings
Write-Host "⚙️  Step 10: Configuring app settings..." -ForegroundColor Green

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

# Step 11: Deploy the application
Write-Host "📦 Step 11: Deploying application code..." -ForegroundColor Green

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
Write-Host "   AI Hub: $AI_HUB_NAME"
Write-Host "   AI Project: $AI_PROJECT_NAME"
Write-Host "   OpenAI: $OPENAI_NAME"
Write-Host "   Model Deployment: $DEPLOYMENT_NAME"
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
