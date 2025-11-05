# 🚀 Quick Deploy Script (Azure Container Storage Variant) - Azure CLI Version
# This script creates an AKS cluster configured with Azure Container Storage (local NVMe)
# It deploys the Minecraft demo workload using the local-csi driver storage class

param(
    [string]$Prefix = "",
    [string]$Region = "northeurope",
    [string]$KubernetesVersion = "1.31.10"
)

# Error handling function
function Test-AzureOperation {
    param(
        [string]$OperationName,
        [scriptblock]$Operation,
        [bool]$ContinueOnError = $false
    )

    Write-Host "🔄 $OperationName..." -ForegroundColor Yellow
    try {
        $result = & $Operation
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ $OperationName failed with exit code $LASTEXITCODE" -ForegroundColor Red
            if (-not $ContinueOnError) {
                Write-Host "🛑 Deployment stopped due to critical error" -ForegroundColor Red
                exit 1
            }
            return $null
        }
        Write-Host "✅ $OperationName completed successfully" -ForegroundColor Green
        return $result
    } catch {
        Write-Host "❌ $OperationName failed: $_" -ForegroundColor Red
        if (-not $ContinueOnError) {
            Write-Host "🛑 Deployment stopped due to critical error" -ForegroundColor Red
            exit 1
        }
        return $null
    }
}

# Check Azure CLI installation and login
function Test-AzurePrerequisites {
    Write-Host "🔍 Checking Azure CLI prerequisites..." -ForegroundColor Yellow

    # Check if Azure CLI is installed
    try {
        $null = az --version
        if ($LASTEXITCODE -ne 0) {
            throw "Azure CLI not found"
        }
    } catch {
        Write-Host "❌ Azure CLI is not installed or not in PATH" -ForegroundColor Red
        Write-Host "Please install Azure CLI from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli" -ForegroundColor Yellow
        exit 1
    }

    # Check if logged in
    try {
        $account = az account show --output json 2>$null | ConvertFrom-Json
        if (-not $account) {
            throw "Not logged in"
        }
        Write-Host "✅ Logged in as $($account.user.name) in subscription $($account.name)" -ForegroundColor Green
    } catch {
        Write-Host "❌ Not logged into Azure CLI" -ForegroundColor Red
        Write-Host "Please run 'az login' first" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "🎮 Minecraft AKS Exhibition Demo - Quick Deploy (Azure CLI)" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green

# Test prerequisites first
Test-AzurePrerequisites

# Ensure the k8s-extension is available (required for Azure Container Storage operations)
Test-AzureOperation -OperationName "Ensuring 'k8s-extension' Azure CLI extension is installed" -Operation {
    az extension add --upgrade --name k8s-extension --output none 2>$null
} -ContinueOnError $true

# Get prefix if not provided
if (-not $Prefix) {
    $Prefix = Read-Host "Enter a prefix for your resources (3-10 chars, lowercase letters/numbers only)"
    if (-not $Prefix -or $Prefix.Length -lt 3 -or $Prefix.Length -gt 10 -or $Prefix -notmatch '^[a-z0-9]+$') {
        Write-Host "❌ Invalid prefix. Must be 3-10 characters, lowercase letters and numbers only." -ForegroundColor Red
        exit 1
    }
} elseif ($Prefix.Length -lt 3 -or $Prefix.Length -gt 10 -or $Prefix -notmatch '^[a-z0-9]+$') {
    Write-Host "❌ Invalid prefix provided. Must be 3-10 characters, lowercase letters and numbers only." -ForegroundColor Red
    exit 1
}

# Validate region
$validRegions = @("eastus", "westus", "westus2", "centralus", "northeurope", "westeurope", "eastasia", "southeastasia", "australiaeast", "uksouth")
if ($Region -notin $validRegions) {
    Write-Host "⚠️ Warning: Region '$Region' may not be tested. Common regions: eastus, westus2, westeurope" -ForegroundColor Yellow
    $continue = Read-Host "Continue anyway? (yes/no)"
    if ($continue -notmatch '^(y|yes)$') {
        exit 0
    }
}

Write-Host "✅ Using prefix: $Prefix" -ForegroundColor Green
Write-Host "✅ Using region: $Region" -ForegroundColor Green
Write-Host "✅ Using Kubernetes version: $KubernetesVersion" -ForegroundColor Green

$ErrorActionPreference = "Stop"

# Resource names
$ResourceGroup = "rg-$Prefix-minecraft-aks-demo"
$AksClusterName = "$Prefix-minecraft-aks"

Write-Host ""
Write-Host "📋 Resource Configuration:" -ForegroundColor Cyan
Write-Host "  Resource Group: $ResourceGroup" -ForegroundColor White
Write-Host "  AKS Cluster: $AksClusterName" -ForegroundColor White
Write-Host "  Region: $Region" -ForegroundColor White
Write-Host ""

# Step 1: Create Resource Group
Test-AzureOperation -OperationName "Creating resource group '$ResourceGroup'" -Operation {
    az group create --name $ResourceGroup --location $Region --output none
}

# Step 2: Create AKS Cluster
try {
    $existingClusterJson = az aks show --resource-group $ResourceGroup --name $AksClusterName --output json 2>$null
    if ($LASTEXITCODE -eq 0 -and $existingClusterJson) {
        Write-Host "✅ AKS cluster '$AksClusterName' already exists, skipping creation" -ForegroundColor Green
    } else {
        Test-AzureOperation -OperationName "Creating AKS cluster '$AksClusterName' (this takes 10-15 minutes)" -Operation {
            az aks create `
                --resource-group $ResourceGroup `
                --name $AksClusterName `
                --location $Region `
                --node-count 2 `
                --node-vm-size Standard_L16s_v3 `
                --kubernetes-version $KubernetesVersion `
                --enable-addons monitoring `
                --enable-azure-container-storage `
                --network-plugin azure `
                --network-policy azure `
                --service-cidr "10.0.0.0/16" `
                --dns-service-ip "10.0.0.10" `
                --generate-ssh-keys `
                --enable-managed-identity `
                --tag "azd-env-name=rg-$Prefix-minecraft-aks-demo" `
                --output none
        }
    }
} catch {
    Write-Host "❌ Failed to create or check AKS cluster: $_" -ForegroundColor Red
    exit 1
}

Write-Host "✅ All infrastructure created successfully!" -ForegroundColor Green

# Step 3: Configure kubectl credentials
Test-AzureOperation -OperationName "Configuring kubectl credentials" -Operation {
    az aks get-credentials --resource-group $ResourceGroup --name $AksClusterName --overwrite-existing --output none
}

# Step 4: Wait for nodes to be ready
Write-Host "⏳ Waiting for AKS nodes to be ready..." -ForegroundColor Yellow
$maxAttempts = 40
$attempt = 0
$nodesReady = $false

do {
    $attempt++
    try {
        $nodes = kubectl get nodes --no-headers 2>$null
        if ($LASTEXITCODE -eq 0 -and $nodes) {
            $readyNodes = $nodes | Where-Object { $_ -match '\sReady\s' }
            $totalNodes = @($nodes).Count
            $readyCount = @($readyNodes).Count

            Write-Host "   Nodes: $readyCount/$totalNodes ready (attempt $attempt/$maxAttempts)" -ForegroundColor Cyan

            if ($readyCount -gt 0 -and $readyCount -eq $totalNodes) {
                $nodesReady = $true
                Write-Host "✅ All AKS nodes are ready!" -ForegroundColor Green
                break
            }
        } else {
            Write-Host "   Waiting for kubectl to connect... (attempt $attempt/$maxAttempts)" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "   Checking nodes... (attempt $attempt/$maxAttempts)" -ForegroundColor Cyan
    }

    if ($attempt -lt $maxAttempts) {
        Start-Sleep 15
    }
} while ($attempt -lt $maxAttempts)

if (-not $nodesReady) {
    Write-Host "⚠️ Warning: Not all nodes ready after $maxAttempts attempts, but continuing..." -ForegroundColor Yellow
}

# Step 5: Apply Kubernetes manifests
Write-Host "🚀 Deploying Minecraft to Kubernetes..." -ForegroundColor Yellow

# First, create storage class for Azure Container Storage (local NVMe)
$storageClassYaml = @"
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local
provisioner: localdisk.csi.acstor.io
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
"@

$storageClassYaml | kubectl apply -f - 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ Storage class created successfully" -ForegroundColor Green
} else {
    Write-Host "⚠️ Warning: Storage class creation may have failed" -ForegroundColor Yellow
}

# Apply the main Kubernetes manifests
$manifestFiles = @(
    "k8s/minecraft-localnvme-pvc.yaml",
    "k8s/minecraft-deployment.yaml",
    "k8s/minecraft-service.yaml"
)

foreach ($manifestFile in $manifestFiles) {
    if (Test-Path $manifestFile) {
        Test-AzureOperation -OperationName "Applying $manifestFile" -Operation {
            kubectl apply -f $manifestFile
        } -ContinueOnError $true
    } else {
        Write-Host "⚠️ Warning: Manifest file $manifestFile not found" -ForegroundColor Yellow
    }
}

# Step 9: Wait for Minecraft pod to be ready
Write-Host "⏳ Waiting for Minecraft pod to be ready..." -ForegroundColor Yellow
$maxAttempts = 20
$attempt = 0

do {
    $attempt++
    try {
        $pods = kubectl get pods -l app=minecraft --no-headers 2>$null
        if ($LASTEXITCODE -eq 0 -and $pods) {
            $runningPods = $pods | Where-Object { $_ -match '\sRunning\s' }
            if ($runningPods) {
                Write-Host "✅ Minecraft pod is running!" -ForegroundColor Green
                break
            }
        }
        Write-Host "   Waiting for Minecraft pod... (attempt $attempt/$maxAttempts)" -ForegroundColor Cyan
    } catch {
        Write-Host "   Checking pods... (attempt $attempt/$maxAttempts)" -ForegroundColor Cyan
    }

    if ($attempt -lt $maxAttempts) {
        Start-Sleep 15
    }
} while ($attempt -lt $maxAttempts)

# Step 10: Get connection information
Write-Host ""
Write-Host "🎯 Getting connection information..." -ForegroundColor Yellow

try {
    $service = kubectl get service minecraft-service -o json 2>$null | ConvertFrom-Json
    if ($service -and $service.status.loadBalancer.ingress) {
        $externalIP = $service.status.loadBalancer.ingress[0].ip
        Write-Host ""
        Write-Host "🎮 MINECRAFT SERVER READY!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "📡 Server IP: $externalIP" -ForegroundColor White
        Write-Host "🔌 Port: 25565" -ForegroundColor White
        Write-Host "-> Connect to: $externalIP:25565" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Host "⏳ Load balancer IP not yet assigned. Use 'kubectl get service minecraft-service' to check later." -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠️ Could not retrieve service information. Use 'kubectl get service minecraft-service' to check manually." -ForegroundColor Yellow
}

# Final status
Write-Host ""
Write-Host "🏗️ Infrastructure Created:" -ForegroundColor Cyan
Write-Host "  AKS Cluster: $AksClusterName" -ForegroundColor White
Write-Host "  Resource Group: $ResourceGroup" -ForegroundColor White
Write-Host "  Region: $Region" -ForegroundColor White
Write-Host ""
Write-Host "📋 Next Steps:" -ForegroundColor Cyan
Write-Host "  1. Wait for the Load Balancer to assign an external IP" -ForegroundColor White
Write-Host "  2. Connect to Minecraft using the external IP on port 25565" -ForegroundColor White
Write-Host "  3. Use './scripts/cleanup.ps1 -Prefix $Prefix' to clean up resources" -ForegroundColor White
Write-Host ""
Write-Host "🎉 Deployment completed successfully!" -ForegroundColor Green
