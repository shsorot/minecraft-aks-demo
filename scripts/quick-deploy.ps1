#  Quick Deploy Script for Exhibition - Azure CLI Version
# This script creates AKS cluster and storage using Azure CLI commands
# Converted from Bicep/ARM templates for better reliability and transparency

param(
    [string]$Prefix = "",
    [string]$Region = "eastus2",
    [string]$KubernetesVersion = "1.32.7",
    [ValidateSet("files", "nvme")]
    [string]$Storage = "files"
)

# Initialize script-level variables
$script:StorageAccount = $null
$ScriptRoot = Split-Path -Parent $PSCommandPath
$ProjectRoot = Split-Path -Parent $ScriptRoot

function Test-ResourcePrefix {
    param([string]$Value)

    if (-not $Value -or $Value.Length -lt 3 -or $Value.Length -gt 10 -or $Value -notmatch '^[a-z0-9]+$') {
        Write-Host " Invalid prefix. Must be 3-10 characters, lowercase letters and numbers only." -ForegroundColor Red
        exit 1
    }
}

# Error handling function
function Test-AzureOperation {
    param(
        [string]$OperationName,
        [scriptblock]$Operation,
        [bool]$ContinueOnError = $false
    )

    Write-Host " $OperationName..." -ForegroundColor Yellow
    try {
        $result = & $Operation
        if ($LASTEXITCODE -ne 0) {
            Write-Host " $OperationName failed with exit code $LASTEXITCODE" -ForegroundColor Red
            if (-not $ContinueOnError) {
                Write-Host " Deployment stopped due to critical error" -ForegroundColor Red
                exit 1
            }
            return $null
        }
        Write-Host " $OperationName completed successfully" -ForegroundColor Green
        return $result
    } catch {
        Write-Host " $OperationName failed: $_" -ForegroundColor Red
        if (-not $ContinueOnError) {
            Write-Host " Deployment stopped due to critical error" -ForegroundColor Red
            exit 1
        }
        return $null
    }
}

# Check Azure CLI installation and login
function Test-AzurePrerequisites {
    Write-Host " Checking Azure CLI prerequisites..." -ForegroundColor Yellow

    # Check if Azure CLI is installed
    try {
        $null = az --version
        if ($LASTEXITCODE -ne 0) {
            throw "Azure CLI not found"
        }
    } catch {
        Write-Host " Azure CLI is not installed or not in PATH" -ForegroundColor Red
        Write-Host "Please install Azure CLI from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli" -ForegroundColor Yellow
        exit 1
    }

    # Check if logged in
    try {
        $account = az account show --output json 2>$null | ConvertFrom-Json
        if (-not $account) {
            throw "Not logged in"
        }
        Write-Host " Logged in as $($account.user.name) in subscription $($account.name)" -ForegroundColor Green
    } catch {
        Write-Host " Not logged into Azure CLI" -ForegroundColor Red
        Write-Host "Please run 'az login' first" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host " Minecraft AKS Exhibition Demo - Quick Deploy (Azure CLI)" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green

# Test prerequisites first
Test-AzurePrerequisites

# Get prefix if not provided
if (-not $Prefix) {
    $Prefix = Read-Host "Enter a prefix for your resources (3-10 chars, lowercase letters/numbers only)"
}

Test-ResourcePrefix -Value $Prefix

# Validate region
$validRegions = @("eastus", "westus", "westus2", "centralus", "northeurope", "westeurope", "eastasia", "southeastasia", "australiaeast", "uksouth")
if ($Region -notin $validRegions) {
    Write-Host " Warning: Region '$Region' may not be tested. Common regions: eastus, westus2, westeurope" -ForegroundColor Yellow
    $continue = Read-Host "Continue anyway? (yes/no)"
    if ($continue -notmatch '^(y|yes)$') {
        exit 0
    }
}

Write-Host " Using prefix: $Prefix" -ForegroundColor Green
Write-Host " Using region: $Region" -ForegroundColor Green
Write-Host " Using Kubernetes version: $KubernetesVersion" -ForegroundColor Green
Write-Host " Using storage type: $Storage" -ForegroundColor Green

$usingNvme = ($Storage -eq "nvme")

$ErrorActionPreference = "Stop"

# Resource names
$ResourceGroup = "rg-$Prefix-minecraft-aks-demo"
$AksClusterName = "$Prefix-minecraft-aks"
if (-not $usingNvme) {
    $storageAccountName = "$($Prefix)storage$((Get-Random -Maximum 999).ToString().PadLeft(3,'0'))"
} else {
    $storageAccountName = $null
}

Write-Host ""
Write-Host " Resource Configuration:" -ForegroundColor Cyan
Write-Host "  Resource Group: $ResourceGroup" -ForegroundColor White
Write-Host "  AKS Cluster: $AksClusterName" -ForegroundColor White
if ($usingNvme) {
    Write-Host "  Storage Type: Azure Container Storage (local NVMe)" -ForegroundColor White
} else {
    Write-Host "  Storage Account: $storageAccountName" -ForegroundColor White
}
Write-Host "  Region: $Region" -ForegroundColor White
Write-Host ""

if ($usingNvme) {
    Test-AzureOperation -OperationName "Installing Azure Container Storage CLI extension" -Operation {
        az extension add --upgrade --name k8s-extension --output none
    }
}

# Step 1: Create Resource Group
Test-AzureOperation -OperationName "Creating resource group '$ResourceGroup'" -Operation {
    az group create --name $ResourceGroup --location $Region --output none
}

# Step 2: Create AKS Cluster
$ErrorActionPreference = "SilentlyContinue"
$existingClusterJson = az aks show --resource-group $ResourceGroup --name $AksClusterName --output json 2>&1 | Where-Object { $_ -notmatch "WARNING" }
$ErrorActionPreference = "Stop"
if ($LASTEXITCODE -eq 0 -and $existingClusterJson) {
    Write-Host " AKS cluster '$AksClusterName' already exists, skipping creation" -ForegroundColor Green
} else {
    Test-AzureOperation -OperationName "Creating AKS cluster '$AksClusterName' (this takes 10-15 minutes)" -Operation {
        $clusterArgs = @(
            "aks", "create",
            "--resource-group", $ResourceGroup,
            "--name", $AksClusterName,
            "--location", $Region,
            "--kubernetes-version", $KubernetesVersion,
            "--enable-addons", "monitoring",
            "--network-plugin", "azure",
            "--network-policy", "azure",
            "--service-cidr", "10.0.0.0/16",
            "--dns-service-ip", "10.0.0.10",
            "--generate-ssh-keys",
            "--enable-managed-identity",
            "--tag", "azd-env-name=rg-$Prefix-minecraft-aks-demo"
        )

        if ($usingNvme) {
            $clusterArgs += @(
                "--node-count", "2",
                "--node-vm-size", "Standard_L16s_v3",
                "--enable-azure-container-storage"
            )
        } else {
            $clusterArgs += @(
                "--node-count", "2",
                "--node-vm-size", "Standard_D2s_v5",
                "--enable-cluster-autoscaler",
                "--min-count", "1",
                "--max-count", "5"
            )
        }

        $clusterArgs += @("--output", "none")
        & az @clusterArgs
    }
}

if (-not $usingNvme) {
    # Step 3: Create Storage Account
    # Check for existing storage accounts with our prefix pattern
    Write-Host " Checking for existing storage accounts..." -ForegroundColor Yellow
    try {
        $queryFilter = "[?starts_with(name,'$Prefix')]"
        $existingStorageJson = az storage account list --resource-group $ResourceGroup --query $queryFilter --output json 2>$null
        if ($LASTEXITCODE -eq 0 -and $existingStorageJson) {
            $existingStorage = $existingStorageJson | ConvertFrom-Json
            if ($existingStorage -and $existingStorage.Count -gt 0) {
                $storageAccountName = $existingStorage[0].name
                Write-Host " Using existing storage account '$storageAccountName'" -ForegroundColor Green
            } else {
                $existingStorage = $null
            }
        } else {
            $existingStorage = $null
        }
    } catch {
        Write-Host " Warning: Could not check existing storage accounts: $_" -ForegroundColor Yellow
        $existingStorage = $null
    }

    if (-not $existingStorage) {
        Test-AzureOperation -OperationName "Creating Premium storage account '$storageAccountName'" -Operation {
            az storage account create `
                --resource-group $ResourceGroup `
                --name $storageAccountName `
                --location $Region `
                --sku Premium_LRS `
                --kind FileStorage `
                --https-only true `
                --min-tls-version TLS1_2 `
                --tag "azd-env-name=rg-$Prefix-minecraft-aks-demo" `
                --output none
        }
    }

    # Step 4: Create File Share
    try {
        $existingShareResult = az storage share exists --name "minecraft-data" --account-name $storageAccountName --query "exists" --output tsv 2>$null
        $existingShare = ($LASTEXITCODE -eq 0 -and $existingShareResult -eq "true")
    } catch {
        $existingShare = $false
    }

    if ($existingShare) {
        Write-Host " File share 'minecraft-data' already exists" -ForegroundColor Green
    } else {
        Test-AzureOperation -OperationName "Creating file share 'minecraft-data'" -Operation {
            az storage share create `
                --name "minecraft-data" `
                --account-name $storageAccountName `
                --quota 100 `
                --output none
        }
    }

    # Step 5: Configure Storage Access Permissions
    $aksPrincipalId = Test-AzureOperation -OperationName "Retrieving AKS managed identity" -Operation {
        $principalId = az aks show --resource-group $ResourceGroup --name $AksClusterName --query "identity.principalId" --output tsv
        if (-not $principalId) {
            throw "Failed to retrieve AKS managed identity principal ID"
        }
        return $principalId
    }

    $storageResourceId = Test-AzureOperation -OperationName "Retrieving storage account resource ID" -Operation {
        $resourceId = az storage account show --resource-group $ResourceGroup --name $storageAccountName --query "id" --output tsv
        if (-not $resourceId) {
            throw "Failed to retrieve storage account resource ID"
        }
        return $resourceId
    }

    # Assign storage permissions
    Test-AzureOperation -OperationName "Assigning storage permissions to AKS managed identity" -Operation {
        az role assignment create `
            --assignee $aksPrincipalId `
            --role "Contributor" `
            --scope $storageResourceId `
            --output none
    } -ContinueOnError $true

    # Store storage account name for later use
    $script:StorageAccount = $storageAccountName
} else {
    Write-Host " Skipping Azure Files storage account creation for NVMe deployments" -ForegroundColor Yellow
    $script:StorageAccount = "Azure Container Storage (local NVMe)"
}

Write-Host " All infrastructure created successfully!" -ForegroundColor Green

# Step 6: Configure kubectl credentials
Test-AzureOperation -OperationName "Configuring kubectl credentials" -Operation {
    az aks get-credentials --resource-group $ResourceGroup --name $AksClusterName --overwrite-existing --output none
}

# Step 7: Wait for nodes to be ready
Write-Host " Waiting for AKS nodes to be ready..." -ForegroundColor Yellow
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
                Write-Host " All AKS nodes are ready!" -ForegroundColor Green
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
    Write-Host " Warning: Not all nodes ready after $maxAttempts attempts, but continuing..." -ForegroundColor Yellow
}

# Step 8: Apply Kubernetes manifests
Write-Host " Deploying Minecraft to Kubernetes..." -ForegroundColor Yellow

if ($usingNvme) {
    $storageClassYaml = @'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local
provisioner: localdisk.csi.acstor.io
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
'@
} else {
    $storageClassYaml = @'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: azure-file-premium
provisioner: file.csi.azure.com
allowVolumeExpansion: true
parameters:
  resourceGroup: {0}
  storageAccount: {1}
  shareName: minecraft-data
reclaimPolicy: Retain
mountOptions:
  - dir_mode=0777
  - file_mode=0777
  - uid=1000
  - gid=1000
  - mfsymlinks
  - cache=strict
  - nosharesock
'@ -f $ResourceGroup, $storageAccountName
}

$storageClassYaml | kubectl apply -f - 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host " Storage class created successfully" -ForegroundColor Green
} else {
    Write-Host " Warning: Storage class creation may have failed" -ForegroundColor Yellow
}

# Apply the main Kubernetes manifests
$pvcManifest = if ($usingNvme) {
    "$ProjectRoot/k8s/minecraft-pvc-localnvme.yaml"
} else {
    "$ProjectRoot/k8s/minecraft-pvc-azurefiles.yaml"
}

$manifestFiles = @(
    $pvcManifest,
    "$ProjectRoot/k8s/minecraft-deployment.yaml",
    "$ProjectRoot/k8s/minecraft-service.yaml"
)

foreach ($manifestFile in $manifestFiles) {
    if (Test-Path $manifestFile) {
        Test-AzureOperation -OperationName "Applying $manifestFile" -Operation {
            kubectl apply -f $manifestFile
        } -ContinueOnError $true
    } else {
        Write-Host " Warning: Manifest file $manifestFile not found" -ForegroundColor Yellow
    }
}

# Step 9: Wait for Minecraft pod to be ready
Write-Host " Waiting for Minecraft pod to be ready..." -ForegroundColor Yellow
$maxAttempts = 40
$attempt = 0

do {
    $attempt++
    try {
        $pods = kubectl get pods -l app=minecraft-server --no-headers 2>$null
        if ($LASTEXITCODE -eq 0 -and $pods) {
            $runningPods = $pods | Where-Object { $_ -match '\sRunning\s' }
            if ($runningPods) {
                Write-Host " Minecraft pod is running!" -ForegroundColor Green
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
Write-Host " Getting connection information..." -ForegroundColor Yellow

try {
    $service = kubectl get service minecraft-service -o json 2>$null | ConvertFrom-Json
    if ($service -and $service.status.loadBalancer.ingress) {
        $externalIP = $service.status.loadBalancer.ingress[0].ip
        Write-Host ""
        Write-Host " MINECRAFT SERVER READY!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host " Server IP: $externalIP" -ForegroundColor White
        Write-Host " Port: 25565" -ForegroundColor White
        Write-Host " Connect to: ${externalIP}:25565" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Host " Load balancer IP not yet assigned. Use 'kubectl get service minecraft-service' to check later." -ForegroundColor Yellow
    }
} catch {
    Write-Host " Could not retrieve service information. Use 'kubectl get service minecraft-service' to check manually." -ForegroundColor Yellow
}

# Final status
Write-Host ""
Write-Host " Infrastructure Created:" -ForegroundColor Cyan
Write-Host "  AKS Cluster: $AksClusterName" -ForegroundColor White
if ($usingNvme) {
    Write-Host "  Storage: Azure Container Storage (local NVMe)" -ForegroundColor White
} else {
    Write-Host "  Storage Account: $script:StorageAccount" -ForegroundColor White
}
Write-Host "  Resource Group: $ResourceGroup" -ForegroundColor White
Write-Host "  Region: $Region" -ForegroundColor White
Write-Host ""
Write-Host " Next Steps:" -ForegroundColor Cyan
Write-Host "  1. Wait for the Load Balancer to assign an external IP" -ForegroundColor White
Write-Host "  2. Connect to Minecraft using the external IP on port 25565" -ForegroundColor White
Write-Host "  3. Use './scripts/cleanup.ps1 -Prefix $Prefix' to clean up resources" -ForegroundColor White
Write-Host ""
Write-Host " Deployment completed successfully!" -ForegroundColor Green
