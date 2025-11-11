<p align="center">
  <img src="https://img.shields.io/badge/Minecraft%20on-Azure%20Kubernetes%20Service-0078D4?logo=microsoft-azure&logoColor=white" alt="Minecraft on AKS" />
  <br>
  <strong>Production-ready Minecraft Java Edition demo for exhibitions, hackathons, and executive briefings.</strong>
  <br>
  Persistent worlds • Live pod-failure demos • One command deploy
</p>

<p align="center">
  <a href="https://learn.microsoft.com/azure/aks/"><img src="https://img.shields.io/badge/AKS-1.32.7-brightgreen?logo=kubernetes&logoColor=white" alt="AKS version" /></a>
  <a href="https://learn.microsoft.com/powershell/"><img src="https://img.shields.io/badge/PowerShell-7+-blue?logo=powershell&logoColor=white" alt="PowerShell" /></a>
  <a href="https://learn.microsoft.com/cli/azure/install-azure-cli"><img src="https://img.shields.io/badge/Azure%20CLI-2.63+-0078D4?logo=microsoft-azure&logoColor=white" alt="Azure CLI" /></a>
  <img src="https://img.shields.io/github/stars/eh8/minecraft-aks-demo?style=flat&logo=github" alt="GitHub stars" />
</p>

---

## Highlights

- 🎯 **One script to stage an entire AKS environment** (resource group, cluster, storage, Kubernetes manifests, monitoring)
- 🔁 **Live pod failure and recovery demo** with guaranteed LoadBalancer IP consistency
- 🗃️ **Dual storage backends**: Azure Files Premium (default) or Azure Container Storage on node-local NVMe
- 📡 **Real-time observability** via Azure Monitor add-on and `kubectl` watchers
- 🔐 **Enterprise guardrails**: Managed identity, network policies, resource limits, liveness/readiness probes
- 🧹 **Fast cleanup** script for repeatable demos and cost control

## Storage modes

| Mode | Use when… | Node profile | Persistence | Extras |
| --- | --- | --- | --- | --- |
| `-Storage files` *(default)* | You want autoscaling, lower cost, simple operations | `Standard_D2s_v3`, autoscaler 1-5 nodes | Azure Files Premium share (100 GB) | Applies to all `EXHIBITION_*` guides
| `-Storage nvme` | You need ultra-low latency or high TPS world edits | `Standard_L16s_v3`, fixed 2 nodes | Azure Container Storage backed by node-local NVMe | Installs ACS extension + local disk StorageClass

> [!NOTE]
> The exhibition guide currently covers only the Azure Files path. NVMe runs follow the same app flow but use different infrastructure commands.

## Demo workflow at a glance

1. **Deploy** `quick-deploy.ps1` with your prefix (≈15 minutes)
2. **Share** the public IP shown at the end of the script with players/viewers
3. **Demo** pod restarts, scaling, and log streaming using the commands below
4. **Clean up** with `cleanup.ps1` or delete the resource group when finished

## Getting started

### Prerequisites

- Azure subscription with AKS quota for the chosen VM size
- Azure CLI logged in (`az login`)
- PowerShell 5.1 (Windows) or PowerShell 7+ (macOS/Linux)

### Deploy everything

```powershell
# Clone and enter the repo
 git clone https://github.com/eh8/minecraft-aks-demo.git
 cd minecraft-aks-demo

# Azure Files (default)
 .\scripts\quick-deploy.ps1 -Prefix "demo01" -Region "northeurope"

# Azure Container Storage on NVMe
 .\scripts\quick-deploy.ps1 -Prefix "demo01" -Region "northeurope" -Storage "nvme"
```

> [!TIP]
> Prefix must be 3-10 lowercase alphanumerics and becomes part of every resource name (e.g., `rg-demo01-minecraft-aks-demo`).

### What the script creates

1. Resource group tagged for easy tracking
2. AKS cluster (`demo01-minecraft-aks`): autoscaling 1-5 nodes (Files) or fixed 2×L16s_v3 (NVMe)
3. Storage backend: Azure Files Premium share or Azure Container Storage (local NVMe disks)
4. Kubernetes manifests (`k8s/`) for deployment, service, and storage class/PVC
5. Monitoring: Azure Monitor addon plus helpful status output in the console

## Verify the deployment

```powershell
# Confirm nodes and pods
kubectl get nodes -o wide
kubectl get pods -l app=minecraft-server -w

# Capture LoadBalancer IP for players
kubectl get service minecraft-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Tail server logs during the show
kubectl logs -l app=minecraft-server -f
```

### Pod restart demo scriptlet

```powershell
$initialPod = kubectl get pod -l app=minecraft-server -o jsonpath='{.items[0].metadata.name}'
$initialIP  = kubectl get service minecraft-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

kubectl delete pod -l app=minecraft-server
kubectl rollout status deployment/minecraft-server --timeout=300s

$newPod = kubectl get pod -l app=minecraft-server -o jsonpath='{.items[0].metadata.name}'
$newIP  = kubectl get service minecraft-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

Write-Host "Pod changed: $initialPod -> $newPod" -ForegroundColor Green
Write-Host "IP consistent: $initialIP" -ForegroundColor Green
```

## Useful commands

```powershell
# Automated IP consistency check
.\scripts\test-ip-consistency.ps1

# List all demo deployments before teardown
.\scripts\cleanup.ps1 -ListOnly

# Remove a specific prefix (deletes AKS + storage)
.\scripts\cleanup.ps1 -Prefix "demo01"

# Deep clean via Azure CLI (fallback)
az group delete --name rg-demo01-minecraft-aks-demo --yes
```

## Troubleshooting Cheatsheet

| Issue | What to check |
| --- | --- |
| LoadBalancer IP pending | `kubectl describe service minecraft-service` (allow up to 10 minutes) |
| Pod stuck in `ContainerCreating` | `kubectl describe pod -l app=minecraft-server` for events; validate storage permissions |
| Storage mount failures | `kubectl describe pvc minecraft-pvc*` and ensure the AKS managed identity has Contributor rights on the storage account |
| `kubectl` cannot reach cluster | Re-run `az aks get-credentials --resource-group rg-<prefix>-minecraft-aks-demo --name <prefix>-minecraft-aks` |
