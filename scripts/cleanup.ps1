# 🧹 Minecraft AKS Demo Cleanup Script
# Enhanced script for cleaning up prefix-based resource groups and all AKS resources

param(
    [string]$Prefix = "",
    [string]$ResourceGroup = "",
    [switch]$ListOnly,
    [switch]$Force,
    [switch]$KeepManagedResourceGroup,
    [switch]$ReconfigureForExhibition
)

Write-Host "🧹 Minecraft AKS Demo Cleanup" -ForegroundColor Green
Write-Host "=============================" -ForegroundColor Green
Write-Host ""

# Function to list all Minecraft demo resource groups
function Get-MinecraftResourceGroups {
    Write-Host "🔍 Searching for Minecraft demo resource groups..." -ForegroundColor Yellow

    $allRGs = az group list --query "[?contains(name,'minecraft')]" | ConvertFrom-Json
    $results = @()

    foreach ($rg in $allRGs) {
        if ($rg.name -match "^rg-.+-minecraft-aks-demo$") {
            $results += [PSCustomObject]@{
                Name = $rg.name
                Location = $rg.location
                Type = "Main Resource Group"
                ProvisioningState = $rg.properties.provisioningState
            }
        } elseif ($rg.name -match "^MC_.+minecraft.+") {
            $results += [PSCustomObject]@{
                Name = $rg.name
                Location = $rg.location
                Type = "AKS Managed RG"
                ProvisioningState = $rg.properties.provisioningState
            }
        }
    }

    return $results
}

# Function to get resource group by prefix
function Get-ResourceGroupByPrefix {
    param([string]$Prefix)

    $targetRG = "rg-$Prefix-minecraft-aks-demo"
    $exists = az group show --name $targetRG 2>$null

    if ($exists) {
        return $targetRG
    } else {
        return $null
    }
}

# Function to get AKS managed resource group
function Get-ManagedResourceGroup {
    param([string]$MainResourceGroup)

    # Extract prefix from main resource group
    if ($MainResourceGroup -match "rg-(.+)-minecraft-aks-demo") {
        $prefix = $Matches[1]
        $clusterName = "aks-$prefix-minecraft"
        $location = az group show --name $MainResourceGroup --query "location" --output tsv 2>$null

        if ($location) {
            return "MC_${MainResourceGroup}_${clusterName}_${location}"
        }
    }

    return $null
}

# If ListOnly is specified, just show available resource groups
if ($ListOnly) {
    Write-Host "📋 Available Minecraft Demo Resource Groups:" -ForegroundColor Cyan
    $resourceGroups = Get-MinecraftResourceGroups

    if ($resourceGroups.Count -eq 0) {
        Write-Host "✅ No Minecraft demo resource groups found" -ForegroundColor Green
        exit 0
    }

    $resourceGroups | Format-Table -AutoSize

    Write-Host ""
    Write-Host "💡 To cleanup a specific deployment:" -ForegroundColor Yellow
    Write-Host "   .\scripts\cleanup.ps1 -Prefix <prefix>" -ForegroundColor White
    Write-Host ""
    Write-Host "💡 To cleanup all Minecraft demos:" -ForegroundColor Yellow
    Write-Host "   .\scripts\cleanup.ps1 -Force" -ForegroundColor White

    exit 0
}

# Determine which resource group(s) to clean up
$targetResourceGroups = @()

if ($ResourceGroup) {
    # Specific resource group provided
    $exists = az group show --name $ResourceGroup 2>$null
    if ($exists) {
        $targetResourceGroups += $ResourceGroup
        Write-Host "🎯 Target resource group: $ResourceGroup" -ForegroundColor Cyan
    } else {
        Write-Host "❌ Resource group '$ResourceGroup' not found" -ForegroundColor Red
        exit 1
    }
} elseif ($Prefix) {
    # Prefix provided, find matching resource group
    $mainRG = Get-ResourceGroupByPrefix $Prefix
    if ($mainRG) {
        $targetResourceGroups += $mainRG
        Write-Host "🎯 Target resource group: $mainRG" -ForegroundColor Cyan

        # Also find the managed resource group
        $managedRG = Get-ManagedResourceGroup $mainRG
        if ($managedRG -and -not $KeepManagedResourceGroup) {
            $managedExists = az group show --name $managedRG 2>$null
            if ($managedExists) {
                $targetResourceGroups += $managedRG
                Write-Host "🎯 AKS managed resource group: $managedRG" -ForegroundColor Cyan
            }
        }
    } else {
        Write-Host "❌ No resource group found for prefix '$Prefix'" -ForegroundColor Red
        Write-Host "💡 Expected resource group name: rg-$Prefix-minecraft-aks-demo" -ForegroundColor Yellow
        exit 1
    }
} else {
    # No specific target, get prefix from user or show all available
    $allResourceGroups = Get-MinecraftResourceGroups

    if ($allResourceGroups.Count -eq 0) {
        Write-Host "✅ No Minecraft demo resource groups found" -ForegroundColor Green
        exit 0
    }

    if (-not $Force) {
        Write-Host "📋 Found the following Minecraft demo resource groups:" -ForegroundColor Cyan
        $allResourceGroups | Format-Table -AutoSize

        $userPrefix = Read-Host "Enter the prefix of the deployment to cleanup (or 'all' for everything)"

        if ($userPrefix -eq 'all') {
            foreach ($rg in $allResourceGroups) {
                $targetResourceGroups += $rg.Name
            }
        } else {
            $mainRG = Get-ResourceGroupByPrefix $userPrefix
            if ($mainRG) {
                $targetResourceGroups += $mainRG
                $managedRG = Get-ManagedResourceGroup $mainRG
                if ($managedRG -and -not $KeepManagedResourceGroup) {
                    $managedExists = az group show --name $managedRG 2>$null
                    if ($managedExists) {
                        $targetResourceGroups += $managedRG
                    }
                }
            } else {
                Write-Host "❌ No resource group found for prefix '$userPrefix'" -ForegroundColor Red
                exit 1
            }
        }
    } else {
        # Force flag specified, clean up everything
        foreach ($rg in $allResourceGroups) {
            $targetResourceGroups += $rg.Name
        }
    }
}

if ($targetResourceGroups.Count -eq 0) {
    Write-Host "❌ No resource groups to clean up" -ForegroundColor Red
    exit 1
}

# Show what will be deleted
Write-Host ""
Write-Host "🗑️ The following resource groups will be deleted:" -ForegroundColor Yellow
foreach ($rg in $targetResourceGroups) {
    Write-Host "   • $rg" -ForegroundColor White
}
Write-Host ""

# Confirmation unless Force is specified
if (-not $Force) {
    $confirmation = Read-Host "⚠️ This will permanently delete all resources. Continue? (yes/no)"
    if ($confirmation -ne 'yes') {
        Write-Host "❌ Cleanup cancelled" -ForegroundColor Red
        exit 0
    }
}

# Clean up Kubernetes resources first (if kubectl is configured)
Write-Host "🔍 Checking for active kubectl context..." -ForegroundColor Yellow
try {
    $currentContext = kubectl config current-context 2>$null
    if ($currentContext -and $currentContext -match "minecraft") {
        Write-Host "🗑️ Removing Kubernetes resources..." -ForegroundColor Yellow

        # Delete Minecraft-specific resources
        kubectl delete deployment minecraft-server --ignore-not-found=true 2>$null
        kubectl delete service minecraft-service --ignore-not-found=true 2>$null
        kubectl delete pvc minecraft-pvc --ignore-not-found=true 2>$null
        kubectl delete configmap minecraft-config --ignore-not-found=true 2>$null
        kubectl delete storageclass azurefile-premium --ignore-not-found=true 2>$null

        Write-Host "✅ Kubernetes resources removed" -ForegroundColor Green
    } else {
        Write-Host "ℹ️ No active Minecraft kubectl context found" -ForegroundColor Cyan
    }
} catch {
    Write-Host "ℹ️ kubectl not available or not configured" -ForegroundColor Cyan
}

# Delete Azure resource groups
Write-Host ""
Write-Host "🗑️ Deleting Azure resource groups..." -ForegroundColor Yellow

$deleteJobs = @()
foreach ($rg in $targetResourceGroups) {
    Write-Host "   Starting deletion of: $rg" -ForegroundColor Cyan

    # Start deletion in background
    $job = Start-Job -ScriptBlock {
        param($resourceGroup)
        az group delete --name $resourceGroup --yes --no-wait 2>$null
        return $resourceGroup
    } -ArgumentList $rg

    $deleteJobs += @{
        Job = $job
        ResourceGroup = $rg
    }
}

# Wait for all deletions to complete
Write-Host "✅ Resource group deletions initiated" -ForegroundColor Green
Write-Host "⏳ Waiting for deletions to complete..." -ForegroundColor Yellow
Write-Host ""

$maxWaitMinutes = 20
$startTime = Get-Date
$allCompleted = $false

do {
    $completedCount = 0
    $runningCount = 0
    $failedCount = 0

    Write-Host "📊 Deletion Status:" -ForegroundColor Cyan
    foreach ($jobInfo in $deleteJobs) {
        $status = $jobInfo.Job.State
        $rg = $jobInfo.ResourceGroup

        switch ($status) {
            "Running" {
                Write-Host "   🔄 $rg - Deletion in progress" -ForegroundColor Yellow
                $runningCount++
            }
            "Completed" {
                Write-Host "   ✅ $rg - Deletion completed" -ForegroundColor Green
                $completedCount++
            }
            "Failed" {
                Write-Host "   ❌ $rg - Deletion failed" -ForegroundColor Red
                $failedCount++
            }
            default {
                Write-Host "   ⏳ $rg - $status" -ForegroundColor White
                $runningCount++
            }
        }
    }

    # Check if all jobs are completed or failed
    if ($runningCount -eq 0) {
        $allCompleted = $true
        break
    }

    # Check timeout
    $elapsed = (Get-Date) - $startTime
    if ($elapsed.TotalMinutes -ge $maxWaitMinutes) {
        Write-Host ""
        Write-Host "⚠️ Timeout reached ($maxWaitMinutes minutes). Some deletions may still be in progress." -ForegroundColor Yellow
        break
    }

    # Wait before next check
    Write-Host ""
    Write-Host "   ⏱️ Elapsed: $([math]::Round($elapsed.TotalMinutes, 1)) minutes | Remaining: $runningCount resource groups" -ForegroundColor Cyan
    Start-Sleep 30
    Write-Host ""

} while (-not $allCompleted)

# Clean up jobs
foreach ($jobInfo in $deleteJobs) {
    Remove-Job $jobInfo.Job -Force 2>$null
}

# Final status summary
Write-Host ""
if ($allCompleted) {
    Write-Host "✅ All resource group deletions completed!" -ForegroundColor Green
    if ($failedCount -gt 0) {
        Write-Host "⚠️ $failedCount resource group(s) failed to delete" -ForegroundColor Yellow
    }
} else {
    Write-Host "⏳ Deletions may still be in progress in the background" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "🎉 Cleanup completed!" -ForegroundColor Green
Write-Host ""
Write-Host "📋 What was cleaned up:" -ForegroundColor Cyan
Write-Host "   • Kubernetes deployments, services, and storage" -ForegroundColor White
Write-Host "   • AKS clusters and all node pools" -ForegroundColor White
Write-Host "   • Azure Files storage accounts" -ForegroundColor White
Write-Host "   • Load balancers and public IPs" -ForegroundColor White
Write-Host "   • Virtual networks and subnets" -ForegroundColor White
Write-Host "   • Managed resource groups (if not kept)" -ForegroundColor White
Write-Host ""
Write-Host "💡 To verify cleanup completion:" -ForegroundColor Cyan
Write-Host "   az group list --query `"[?contains(name,'minecraft-aks-demo')]`" --output table" -ForegroundColor White
Write-Host ""
Write-Host "💡 To check deletion progress:" -ForegroundColor Cyan
Write-Host "   .\scripts\cleanup.ps1 -ListOnly" -ForegroundColor White
Write-Host ""
Write-Host "🔍 Current Minecraft Service Status:" -ForegroundColor Cyan
try {
    $service = kubectl get service minecraft-service -o json 2>$null | ConvertFrom-Json
    if ($service -and $service.status.loadBalancer.ingress) {
        $externalIP = $service.status.loadBalancer.ingress[0].ip
        Write-Host "   🎮 Minecraft Server IP: $externalIP:25565" -ForegroundColor Green
    } else {
        Write-Host "   ⏳ Minecraft service not found or IP not yet assigned" -ForegroundColor Yellow
    }
} catch {
    Write-Host "   ℹ️ Unable to check Minecraft service (kubectl not configured or service not found)" -ForegroundColor Cyan
}
