# Cleanup Azure Resources
# Run this script to delete all resources created by the deployment

Write-Host "🗑️  Azure Resource Cleanup" -ForegroundColor Red
Write-Host "==============================" -ForegroundColor Red
Write-Host ""

# Try to load from deployment info
if (Test-Path "deployment-info.json") {
    $info = Get-Content "deployment-info.json" | ConvertFrom-Json
    $RESOURCE_GROUP = $info.ResourceGroup
    Write-Host "📋 Found deployment info:" -ForegroundColor Yellow
    Write-Host "   Resource Group: $RESOURCE_GROUP"
    Write-Host "   Web App: $($info.WebApp)"
    Write-Host "   OpenAI: $($info.OpenAIName)"
    Write-Host ""
} else {
    Write-Host "⚠️  No deployment-info.json found" -ForegroundColor Yellow
    $RESOURCE_GROUP = Read-Host "Enter resource group name (default: triathlon-rg)"
    if ([string]::IsNullOrWhiteSpace($RESOURCE_GROUP)) {
        $RESOURCE_GROUP = "triathlon-rg"
    }
}

Write-Host "⚠️  WARNING: This will delete the entire resource group and all resources within it!" -ForegroundColor Red
Write-Host "   Resource Group: $RESOURCE_GROUP" -ForegroundColor Yellow
Write-Host ""

$confirm = Read-Host "Are you sure you want to continue? Type 'YES' to confirm"

if ($confirm -eq "YES") {
    Write-Host "🗑️  Deleting resource group..." -ForegroundColor Red
    az group delete --name $RESOURCE_GROUP --yes --no-wait
    
    Write-Host "✅ Deletion initiated. Resources will be removed in the background." -ForegroundColor Green
    Write-Host "   You can check status in Azure Portal or with:" -ForegroundColor Yellow
    Write-Host "   az group show --name $RESOURCE_GROUP" -ForegroundColor Cyan
    
    # Remove deployment info file
    if (Test-Path "deployment-info.json") {
        Remove-Item "deployment-info.json"
        Write-Host "   Removed deployment-info.json" -ForegroundColor Green
    }
} else {
    Write-Host "❌ Cleanup cancelled" -ForegroundColor Yellow
}
