# Azure Deployment with Azure OpenAI and Managed Identity
# This script creates everything needed for secure, key-less authentication

Write-Host "🚀 Triathlon App - Azure OpenAI + Managed Identity Deployment" -ForegroundColor Cyan
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host ""

# Configuration
$RESOURCE_GROUP = "triathlon-rg"
$LOCATION = "swedencentral"
$APP_NAME = "triathlon-app-$(Get-Random -Minimum 1000 -Maximum 9999)"
$PLAN_NAME = "triathlon-plan"
$OPENAI_NAME = "triathlon-openai-$(Get-Random -Minimum 1000 -Maximum 9999)"
$DEPLOYMENT_NAME = "gpt-4o-mini"  # or gpt-35-turbo, gpt-4, etc.
$MODEL_NAME = "gpt-4o-mini"
$MODEL_VERSION = "2024-07-18"
$SKU = "B1"  # Basic tier

Write-Host "📋 Configuration:" -ForegroundColor Yellow
Write-Host "  Resource Group: $RESOURCE_GROUP"
Write-Host "  Location: $LOCATION"
Write-Host "  App Name: $APP_NAME"
Write-Host "  OpenAI Name: $OPENAI_NAME"
Write-Host "  Model Deployment: $DEPLOYMENT_NAME ($MODEL_NAME)"
Write-Host ""

# Step 1: Create Resource Group
Write-Host "📦 Step 1: Creating resource group..." -ForegroundColor Green
az group create --name $RESOURCE_GROUP --location $LOCATION
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to create resource group" -ForegroundColor Red
    exit 1
}

# Step 2: Create Azure OpenAI resource
Write-Host "🤖 Step 2: Creating Azure OpenAI resource..." -ForegroundColor Green
Write-Host "   (This may take 2-3 minutes)" -ForegroundColor Yellow
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

# Get the OpenAI endpoint
$OPENAI_ENDPOINT = az cognitiveservices account show `
    --name $OPENAI_NAME `
    --resource-group $RESOURCE_GROUP `
    --query "properties.endpoint" `
    --output tsv

Write-Host "   ✅ Endpoint: $OPENAI_ENDPOINT" -ForegroundColor Green

# Step 3: Deploy the model
Write-Host "🤖 Step 3: Deploying AI model ($MODEL_NAME)..." -ForegroundColor Green
Write-Host "   (This may take 1-2 minutes)" -ForegroundColor Yellow

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
    Write-Host "⚠️  Model deployment failed. You may need to deploy manually in Azure Portal" -ForegroundColor Yellow
    Write-Host "   Or try a different model like gpt-35-turbo" -ForegroundColor Yellow
} else {
    Write-Host "   ✅ Model deployed: $DEPLOYMENT_NAME" -ForegroundColor Green
}

# Step 4: Create App Service Plan
Write-Host "📦 Step 4: Creating App Service plan..." -ForegroundColor Green
az appservice plan create `
    --name $PLAN_NAME `
    --resource-group $RESOURCE_GROUP `
    --location $LOCATION `
    --sku $SKU `
    --is-linux

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to create App Service plan" -ForegroundColor Red
    exit 1
}

# Step 5: Create Web App
Write-Host "🌐 Step 5: Creating Web App..." -ForegroundColor Green
az webapp create `
    --resource-group $RESOURCE_GROUP `
    --plan $PLAN_NAME `
    --name $APP_NAME `
    --runtime "PYTHON:3.11"

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to create Web App" -ForegroundColor Red
    exit 1
}

# Step 6: Enable Managed Identity
Write-Host "🔐 Step 6: Enabling system-assigned managed identity..." -ForegroundColor Green
$IDENTITY_PRINCIPAL_ID = az webapp identity assign `
    --resource-group $RESOURCE_GROUP `
    --name $APP_NAME `
    --query principalId `
    --output tsv

Write-Host "   ✅ Identity Principal ID: $IDENTITY_PRINCIPAL_ID" -ForegroundColor Green

# Wait for identity to propagate
Write-Host "   ⏳ Waiting for identity to propagate (30 seconds)..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# Step 7: Grant Cognitive Services OpenAI User role to the managed identity
Write-Host "🔐 Step 7: Granting Azure OpenAI access to managed identity..." -ForegroundColor Green

# Get the OpenAI resource ID
$OPENAI_RESOURCE_ID = az cognitiveservices account show `
    --name $OPENAI_NAME `
    --resource-group $RESOURCE_GROUP `
    --query id `
    --output tsv

# Assign the Cognitive Services OpenAI User role
az role assignment create `
    --role "Cognitive Services OpenAI User" `
    --assignee $IDENTITY_PRINCIPAL_ID `
    --scope $OPENAI_RESOURCE_ID

if ($LASTEXITCODE -ne 0) {
    Write-Host "⚠️  Role assignment may have failed. Retrying..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    az role assignment create `
        --role "Cognitive Services OpenAI User" `
        --assignee $IDENTITY_PRINCIPAL_ID `
        --scope $OPENAI_RESOURCE_ID
}

Write-Host "   ✅ Permissions granted" -ForegroundColor Green

# Step 8: Configure Web App settings
Write-Host "⚙️  Step 8: Configuring application settings..." -ForegroundColor Green
az webapp config appsettings set `
    --resource-group $RESOURCE_GROUP `
    --name $APP_NAME `
    --settings `
        LLM_PROVIDER="azure_ai" `
        AZURE_AI_ENDPOINT="$OPENAI_ENDPOINT" `
        AZURE_AI_DEPLOYMENT_NAME="$DEPLOYMENT_NAME" `
        AZURE_AI_AUTH="entra_id" `
        AZURE_AI_API_VERSION="2024-02-15-preview" `
        DATABASE_URL="sqlite:///./workouts.db" `
        SCM_DO_BUILD_DURING_DEPLOYMENT="true"

# Step 9: Configure startup command
Write-Host "⚙️  Step 9: Configuring startup command..." -ForegroundColor Green
az webapp config set `
    --resource-group $RESOURCE_GROUP `
    --name $APP_NAME `
    --startup-file "startup.sh"

# Step 10: Enable logging
Write-Host "📝 Step 10: Enabling application logging..." -ForegroundColor Green
az webapp log config `
    --resource-group $RESOURCE_GROUP `
    --name $APP_NAME `
    --application-logging filesystem `
    --detailed-error-messages true `
    --web-server-logging filesystem `
    --level information

# Step 11: Deploy code
Write-Host "📦 Step 11: Deploying application code..." -ForegroundColor Green
Write-Host "   Creating deployment package..." -ForegroundColor Yellow

# Create zip file for deployment
$zipFile = "deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss').zip"
Compress-Archive -Path @(
    "app",
    "requirements.txt",
    "startup.sh"
) -DestinationPath $zipFile -Force

Write-Host "   Uploading to Azure (this may take 2-3 minutes)..." -ForegroundColor Yellow
az webapp deployment source config-zip `
    --resource-group $RESOURCE_GROUP `
    --name $APP_NAME `
    --src $zipFile `
    --timeout 600

# Clean up zip file
Remove-Item $zipFile

# Step 12: Wait for deployment and restart
Write-Host "🔄 Step 12: Restarting web app..." -ForegroundColor Green
az webapp restart --resource-group $RESOURCE_GROUP --name $APP_NAME

Write-Host "   ⏳ Waiting for app to start (30 seconds)..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# Step 13: Test the deployment
Write-Host "🧪 Step 13: Testing deployment..." -ForegroundColor Green
$APP_URL = "https://$APP_NAME.azurewebsites.net"

try {
    $healthCheck = Invoke-RestMethod -Uri "$APP_URL/health" -TimeoutSec 10
    Write-Host "   ✅ Health check passed!" -ForegroundColor Green
    Write-Host "   Status: $($healthCheck.status)" -ForegroundColor Cyan
    Write-Host "   Provider: $($healthCheck.llm_provider)" -ForegroundColor Cyan
} catch {
    Write-Host "   ⚠️  Health check failed. App may still be starting..." -ForegroundColor Yellow
}

# Final output
Write-Host ""
Write-Host "✅ Deployment Complete!" -ForegroundColor Green
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "📊 Deployment Summary:" -ForegroundColor Yellow
Write-Host "  Resource Group:    $RESOURCE_GROUP"
Write-Host "  Azure OpenAI:      $OPENAI_NAME"
Write-Host "  Model Deployment:  $DEPLOYMENT_NAME"
Write-Host "  Web App:           $APP_NAME"
Write-Host "  Authentication:    Managed Identity (Entra ID)"
Write-Host ""
Write-Host "🌐 Your app is available at:" -ForegroundColor Green
Write-Host "   $APP_URL" -ForegroundColor Cyan
Write-Host ""
Write-Host "🔍 Test endpoints:" -ForegroundColor Yellow
Write-Host "   Health:     curl $APP_URL/health"
Write-Host "   Readiness:  curl $APP_URL/health/ready"
Write-Host ""
Write-Host "📊 Useful commands:" -ForegroundColor Yellow
Write-Host "   View logs:         az webapp log tail --resource-group $RESOURCE_GROUP --name $APP_NAME"
Write-Host "   Open portal:       az webapp browse --resource-group $RESOURCE_GROUP --name $APP_NAME"
Write-Host "   SSH access:        az webapp ssh --resource-group $RESOURCE_GROUP --name $APP_NAME"
Write-Host "   Stream logs:       az webapp log tail --resource-group $RESOURCE_GROUP --name $APP_NAME"
Write-Host ""
Write-Host "🔐 Security:" -ForegroundColor Yellow
Write-Host "   ✅ No API keys stored - using Managed Identity"
Write-Host "   ✅ Automatic credential rotation"
Write-Host "   ✅ Azure RBAC for access control"
Write-Host ""

# Save deployment info
$deploymentInfo = @{
    ResourceGroup = $RESOURCE_GROUP
    Location = $LOCATION
    WebApp = $APP_NAME
    AppUrl = $APP_URL
    OpenAIName = $OPENAI_NAME
    OpenAIEndpoint = $OPENAI_ENDPOINT
    DeploymentName = $DEPLOYMENT_NAME
    ManagedIdentityPrincipalId = $IDENTITY_PRINCIPAL_ID
    DeploymentDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
} | ConvertTo-Json

$deploymentInfo | Out-File -FilePath "deployment-info.json" -Encoding utf8
Write-Host "💾 Deployment info saved to: deployment-info.json" -ForegroundColor Cyan
Write-Host ""

# Open browser
$openBrowser = Read-Host "Open the app in your browser? (Y/N)"
if ($openBrowser -eq "Y" -or $openBrowser -eq "y") {
    Start-Process $APP_URL
}

Write-Host ""
Write-Host "🎉 Setup complete! Your app is running with secure Managed Identity authentication." -ForegroundColor Green
