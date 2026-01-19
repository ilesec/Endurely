# Deploy to Azure App Service using EXISTING Azure OpenAI
# This script connects to your existing Azure OpenAI resource

Write-Host "🚀 Triathlon App - Deploy with Existing Azure OpenAI" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""

# Get Azure OpenAI details from user
Write-Host "📋 Enter your existing Azure OpenAI details:" -ForegroundColor Yellow
Write-Host ""

$OPENAI_ENDPOINT = Read-Host "Azure OpenAI Endpoint (e.g., https://your-openai.openai.azure.com/)"
$DEPLOYMENT_NAME = Read-Host "Deployment/Model Name (e.g., gpt-4o-mini, gpt-35-turbo, gpt-4)"
$OPENAI_RESOURCE_GROUP = Read-Host "Azure OpenAI Resource Group (if known, press Enter to skip)"
$OPENAI_NAME = Read-Host "Azure OpenAI Resource Name (if known, press Enter to skip)"

Write-Host ""
Write-Host "📋 App Service Configuration:" -ForegroundColor Yellow
$RESOURCE_GROUP = Read-Host "Resource Group for App Service (default: triathlon-rg)"
if ([string]::IsNullOrWhiteSpace($RESOURCE_GROUP)) {
    $RESOURCE_GROUP = "triathlon-rg"
}

$LOCATION = Read-Host "Location (default: swedencentral)"
if ([string]::IsNullOrWhiteSpace($LOCATION)) {
    $LOCATION = "swedencentral"
}

$APP_NAME = Read-Host "App Service Name (default: triathlon-app-<random>)"
if ([string]::IsNullOrWhiteSpace($APP_NAME)) {
    $APP_NAME = "triathlon-app-$(Get-Random -Minimum 1000 -Maximum 9999)"
}

$PLAN_NAME = "triathlon-plan"
$SKU = "B1"

Write-Host ""
Write-Host "✅ Configuration Summary:" -ForegroundColor Green
Write-Host "  Azure OpenAI Endpoint:  $OPENAI_ENDPOINT"
Write-Host "  Deployment Name:        $DEPLOYMENT_NAME"
Write-Host "  App Service Name:       $APP_NAME"
Write-Host "  Resource Group:         $RESOURCE_GROUP"
Write-Host "  Location:               $LOCATION"
Write-Host ""

$confirm = Read-Host "Proceed with deployment? (Y/N)"
if ($confirm -ne "Y" -and $confirm -ne "y") {
    Write-Host "❌ Deployment cancelled" -ForegroundColor Red
    exit 0
}

# Step 1: Create Resource Group (if needed)
Write-Host ""
Write-Host "📦 Step 1: Creating resource group (if needed)..." -ForegroundColor Green
az group create --name $RESOURCE_GROUP --location $LOCATION 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "   ✅ Resource group ready" -ForegroundColor Green
}

# Step 2: Create App Service Plan
Write-Host "📦 Step 2: Creating App Service plan..." -ForegroundColor Green
$existingPlan = az appservice plan show --name $PLAN_NAME --resource-group $RESOURCE_GROUP 2>$null
if ($existingPlan) {
    Write-Host "   ✅ Using existing plan" -ForegroundColor Green
} else {
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
}

# Step 3: Create Web App
Write-Host "🌐 Step 3: Creating Web App..." -ForegroundColor Green
az webapp create `
    --resource-group $RESOURCE_GROUP `
    --plan $PLAN_NAME `
    --name $APP_NAME `
    --runtime "PYTHON:3.11"

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to create Web App" -ForegroundColor Red
    exit 1
}

# Step 4: Enable Managed Identity
Write-Host "🔐 Step 4: Enabling system-assigned managed identity..." -ForegroundColor Green
$IDENTITY_PRINCIPAL_ID = az webapp identity assign `
    --resource-group $RESOURCE_GROUP `
    --name $APP_NAME `
    --query principalId `
    --output tsv

Write-Host "   ✅ Identity Principal ID: $IDENTITY_PRINCIPAL_ID" -ForegroundColor Green

# Wait for identity to propagate
Write-Host "   ⏳ Waiting for identity to propagate (30 seconds)..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# Step 5: Grant permissions to Azure OpenAI
Write-Host "🔐 Step 5: Granting Azure OpenAI access..." -ForegroundColor Green

if (![string]::IsNullOrWhiteSpace($OPENAI_RESOURCE_GROUP) -and ![string]::IsNullOrWhiteSpace($OPENAI_NAME)) {
    # We have the resource details, assign role
    $OPENAI_RESOURCE_ID = az cognitiveservices account show `
        --name $OPENAI_NAME `
        --resource-group $OPENAI_RESOURCE_GROUP `
        --query id `
        --output tsv 2>$null
    
    if ($OPENAI_RESOURCE_ID) {
        az role assignment create `
            --role "Cognitive Services OpenAI User" `
            --assignee $IDENTITY_PRINCIPAL_ID `
            --scope $OPENAI_RESOURCE_ID
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "   ✅ Permissions granted automatically" -ForegroundColor Green
        } else {
            Write-Host "   ⚠️  Automatic permission assignment failed" -ForegroundColor Yellow
        }
    } else {
        Write-Host "   ⚠️  Could not find OpenAI resource" -ForegroundColor Yellow
    }
} else {
    Write-Host "   ⚠️  OpenAI resource details not provided" -ForegroundColor Yellow
}

# Show manual instructions
Write-Host ""
Write-Host "📝 Manual Permission Setup (if needed):" -ForegroundColor Yellow
Write-Host "   If automatic permission assignment failed, grant access manually:"
Write-Host "   1. Go to Azure Portal: https://portal.azure.com"
Write-Host "   2. Navigate to your Azure OpenAI resource"
Write-Host "   3. Go to 'Access control (IAM)' → 'Add role assignment'"
Write-Host "   4. Select role: 'Cognitive Services OpenAI User'"
Write-Host "   5. Assign access to: 'Managed Identity'"
Write-Host "   6. Select: '$APP_NAME'"
Write-Host "   7. Principal ID: $IDENTITY_PRINCIPAL_ID"
Write-Host ""

# Step 6: Configure App Settings
Write-Host "⚙️  Step 6: Configuring application settings..." -ForegroundColor Green
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

# Step 7: Configure startup
Write-Host "⚙️  Step 7: Configuring startup command..." -ForegroundColor Green
az webapp config set `
    --resource-group $RESOURCE_GROUP `
    --name $APP_NAME `
    --startup-file "startup.sh"

# Step 8: Enable logging
Write-Host "📝 Step 8: Enabling application logging..." -ForegroundColor Green
az webapp log config `
    --resource-group $RESOURCE_GROUP `
    --name $APP_NAME `
    --application-logging filesystem `
    --detailed-error-messages true `
    --web-server-logging filesystem `
    --level information

# Step 9: Deploy code
Write-Host "📦 Step 9: Deploying application code..." -ForegroundColor Green
Write-Host "   Creating deployment package..." -ForegroundColor Yellow

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

Remove-Item $zipFile

# Step 10: Restart app
Write-Host "🔄 Step 10: Restarting web app..." -ForegroundColor Green
az webapp restart --resource-group $RESOURCE_GROUP --name $APP_NAME

Write-Host "   ⏳ Waiting for app to start (30 seconds)..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# Step 11: Test deployment
Write-Host "🧪 Step 11: Testing deployment..." -ForegroundColor Green
$APP_URL = "https://$APP_NAME.azurewebsites.net"

try {
    $healthCheck = Invoke-RestMethod -Uri "$APP_URL/health" -TimeoutSec 10
    Write-Host "   ✅ Health check passed!" -ForegroundColor Green
    Write-Host "   Status: $($healthCheck.status)" -ForegroundColor Cyan
} catch {
    Write-Host "   ⚠️  Health check failed. Checking readiness..." -ForegroundColor Yellow
}

try {
    $readyCheck = Invoke-RestMethod -Uri "$APP_URL/health/ready" -TimeoutSec 10
    Write-Host "   Readiness: $($readyCheck.status)" -ForegroundColor Cyan
    if ($readyCheck.status -eq "not_ready") {
        Write-Host "   Reason: $($readyCheck.reason)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ⚠️  App may still be starting up..." -ForegroundColor Yellow
}

# Final output
Write-Host ""
Write-Host "✅ Deployment Complete!" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "📊 Deployment Summary:" -ForegroundColor Yellow
Write-Host "  Resource Group:        $RESOURCE_GROUP"
Write-Host "  Web App:               $APP_NAME"
Write-Host "  Azure OpenAI Endpoint: $OPENAI_ENDPOINT"
Write-Host "  Deployment Name:       $DEPLOYMENT_NAME"
Write-Host "  Authentication:        Managed Identity (Entra ID)"
Write-Host "  Managed Identity ID:   $IDENTITY_PRINCIPAL_ID"
Write-Host ""
Write-Host "🌐 Your app is available at:" -ForegroundColor Green
Write-Host "   $APP_URL" -ForegroundColor Cyan
Write-Host ""
Write-Host "🔍 Test endpoints:" -ForegroundColor Yellow
Write-Host "   curl $APP_URL/health"
Write-Host "   curl $APP_URL/health/ready"
Write-Host ""
Write-Host "📊 Useful commands:" -ForegroundColor Yellow
Write-Host "   View logs:    az webapp log tail --resource-group $RESOURCE_GROUP --name $APP_NAME"
Write-Host "   Open portal:  az webapp browse --resource-group $RESOURCE_GROUP --name $APP_NAME"
Write-Host "   Restart:      az webapp restart --resource-group $RESOURCE_GROUP --name $APP_NAME"
Write-Host ""

if ($readyCheck.status -eq "not_ready") {
    Write-Host "⚠️  IMPORTANT: App is not ready!" -ForegroundColor Red
    Write-Host "   You may need to manually grant OpenAI permissions (see instructions above)" -ForegroundColor Yellow
    Write-Host "   Then restart the app: az webapp restart --resource-group $RESOURCE_GROUP --name $APP_NAME" -ForegroundColor Yellow
    Write-Host ""
}

# Save deployment info
$deploymentInfo = @{
    ResourceGroup = $RESOURCE_GROUP
    Location = $LOCATION
    WebApp = $APP_NAME
    AppUrl = $APP_URL
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
Write-Host "🎉 Deployment complete!" -ForegroundColor Green
