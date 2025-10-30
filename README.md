# 🎮 Minecraft on Azure Kubernetes Service (AKS) - Exhibition Demo

A production-ready demonstration of deploying Minecraft Java Edition on Azure Kubernetes Service with persistent storage, auto-scaling, and enterprise-grade reliability. Perfect for showcasing cloud-native capabilities at exhibitions and conferences.

## ✨ Key Features

### 🔒 **Enterprise-Ready Infrastructure**
- **Azure LoadBalancer**: External IP assignment with high availability
- **Pod Failure Resilience**: Service remains accessible across pod restarts and failures
- **Azure Files Premium**: High-performance persistent storage for world data
- **AKS Auto-scaling**: Kubernetes cluster scales from 1-5 nodes based on demand
- **Azure Monitor Integration**: Built-in observability and monitoring

### 🚀 **Exhibition-Ready Deployment**
- **One-Click Setup**: Single PowerShell script deploys complete infrastructure
- **Comprehensive Error Handling**: Robust deployment with fail-fast validation
- **Custom Resource Naming**: Easy tracking with prefix-based naming (`rg-{prefix}-minecraft-aks-demo`)
- **Clean Teardown**: Simple resource cleanup with dedicated cleanup script

### 🎯 **Demo Features**
- **Instant Connection Info**: Script displays server IP prominently upon completion
- **Pod Resilience Testing**: Ready for live demonstrations of Kubernetes self-healing
- **Real-time Monitoring**: Watch resource creation and pod status in real-time

## 🚀 Quick Start

### Prerequisites
- Azure CLI installed and logged in (`az login`)
- PowerShell 5.1+ (Windows) or PowerShell Core (Cross-platform)
- Valid Azure subscription with AKS quota for Standard_D2s_v3 VMs

### Deploy Everything
```powershell
# Clone and navigate to the repository
git clone <repository-url>
cd minecraft-java-aks

# Deploy with custom prefix (recommended for exhibitions)
.\scripts\quick-deploy.ps1 -Prefix "demo01" -Region "northeurope"
```

### What Gets Created
The deployment script creates:
1. ✅ **Resource Group**: `rg-demo01-minecraft-aks-demo`
2. ✅ **AKS Cluster**: `demo01-minecraft-aks` with auto-scaling (1-5 nodes)
3. ✅ **Premium Storage**: Azure Files with 100GB quota for world persistence
4. ✅ **Kubernetes Resources**: Deployment, Service, PVC with optimized configuration
5. ✅ **Load Balancer**: External IP for stable connectivity
6. ✅ **Monitoring**: Azure Monitor integration for observability

### Expected Output
```
🎉 DEPLOYMENT SUCCESSFUL!
========================

🎮 Minecraft Server Details:
  Server Address: 40.127.222.166:25565
  Max Players: 64
  Game Mode: Survival

🔒 IP Consistency Guarantee:
  ✅ External IP (40.127.222.166) will remain consistent
  ✅ IP persists across pod restarts, failures, and scaling
  ✅ Azure LoadBalancer provides stable endpoint
  ✅ World data persists on Azure Files Premium storage
```

## 🎭 Exhibition Demonstrations

### Pod Restart Resilience Demo
```powershell
# Show current status
kubectl get pods -l app=minecraft-server -o wide
kubectl get service minecraft-service

# Simulate pod failure
kubectl delete pod -l app=minecraft-server

# Verify IP consistency (should remain the same)
kubectl get service minecraft-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Test connectivity
Test-NetConnection -ComputerName 40.127.222.166 -Port 25565
```

### Automated Consistency Testing
```powershell
# Run comprehensive IP consistency test
.\scripts\test-ip-consistency.ps1
```

### Real-Time Monitoring
```powershell
# Watch pod status during failures
kubectl get pods -l app=minecraft-server -w

# Monitor service health
kubectl get service minecraft-service -w

## 📚 Project Structure

```
minecraft-java-aks/
├── scripts/
│   ├── quick-deploy.ps1      # Main deployment script
│   └── cleanup.ps1           # Resource cleanup script
├── k8s/
│   ├── minecraft-deployment.yaml   # Kubernetes deployment
│   ├── minecraft-service.yaml      # LoadBalancer service
│   └── minecraft-pvc.yaml          # Persistent volume claim
├── README.md                       # This file
├── EXHIBITION_DEMO_GUIDE.md        # Exhibition demonstration guide
└── EXHIBITION_STATUS.md            # Project status and features
```

## 🔧 Cleanup

When your demonstration is complete:

```powershell
# Clean up all resources for a specific deployment
.\scripts\cleanup.ps1 -Prefix "demo01"

# Or list all Minecraft deployments first
.\scripts\cleanup.ps1 -ListOnly
```

The cleanup script will:
- Remove Kubernetes resources (deployments, services, PVC)
- Delete Azure resource groups (main and AKS-managed)
- Clean up storage accounts and networking
- Wait for deletion completion before exiting

## 🎯 Exhibition Tips

1. **Pre-deployment**: Test the deployment in advance to ensure quota and permissions
2. **Demonstration**: Use the pod restart demo to showcase Kubernetes self-healing
3. **Monitoring**: Show Azure Monitor metrics during the demo
4. **Cleanup**: Always run cleanup after demonstrations to avoid costs

## 🔒 Security & Best Practices

- **Managed Identity**: Uses Azure managed identity for secure access to storage
- **Network Policies**: Azure CNI with network policies for security
- **Resource Limits**: CPU and memory limits defined for all containers
- **Health Checks**: Liveness and readiness probes configured
- **Auto-scaling**: Cluster scales based on resource demands (1-5 nodes)

## 📊 Monitoring & Troubleshooting

```powershell
# Check pod status
kubectl get pods -l app=minecraft-server

# View server logs
kubectl logs -l app=minecraft-server -f

# Check service and external IP
kubectl get service minecraft-service

# View resource usage
kubectl top pods
kubectl top nodes
```

## 📊 Configuration Details

### Azure Infrastructure

- **VM Size**: Standard_D4s_v3 (4 vCPU, 16GB RAM) - optimized for 64 player capacity
- **Node Count**: 2 initial nodes, auto-scale 1-5 based on demand
- **Storage**: Azure Files Premium 100GB with Premium_LRS redundancy
- **Networking**: Azure CNI with network policies enabled
- **Region**: North Europe (configurable via -Region parameter)

### Minecraft Server Settings
- **Edition**: Java Edition (latest)
- **Max Players**: 64 concurrent players
- **Game Mode**: Survival
- **Difficulty**: Normal
- **World Type**: Default with custom seed
- **RCON**: Enabled on port 25575 for remote administration

### Client Requirements
- **Download Minecraft Java Edition**: [Free Trial Available](https://www.minecraft.net/en-us/free-trial)
- **Compatibility**: Java Edition clients only (Bedrock not supported)

## 🧹 Cleanup

### Complete Environment Cleanup
```powershell
# Delete entire resource group (recommended)
az group delete --name rg-demo01-minecraft-aks-demo --yes --no-wait
```

### List All Demo Resource Groups
```powershell
# Find all Minecraft demo resource groups for bulk cleanup
az group list --query "[?contains(name, 'minecraft-aks-demo')].name" --output table
```

## 🔍 Troubleshooting

### Common Issues

**External IP not assigned**
```powershell
# Check LoadBalancer status
kubectl describe service minecraft-service
# Wait up to 10 minutes for Azure to provision the IP
```

**Pod won't start**
```powershell
# Check pod status and events
kubectl describe pod -l app=minecraft-server
kubectl get events --sort-by='.lastTimestamp'
```

**Storage mounting issues**
```powershell
# Verify persistent volume claim
kubectl describe pvc minecraft-pvc
# Check storage account permissions
az role assignment list --scope /subscriptions/{subscription}/resourceGroups/{rg}
```

## 🧹 Resource Cleanup

### Quick Cleanup by Prefix

```bash
# List all Minecraft demo deployments
.\scripts\cleanup.ps1 -ListOnly

# Clean up specific deployment (e.g., demo01)
.\scripts\cleanup.ps1 -Prefix demo01

# Clean up all Minecraft demos (with confirmation)
.\scripts\cleanup.ps1 -Force

# Keep managed resource group (advanced)
.\scripts\cleanup.ps1 -Prefix demo01 -KeepManagedResourceGroup
```

### Manual Cleanup

```bash
# Delete specific resource group
az group delete --name rg-{prefix}-minecraft-aks-demo --yes

# List remaining resources
az group list --query "[?contains(name, 'minecraft')]" --output table
```

### Performance Optimization

- **More Players**: Scale deployment replicas or upgrade to larger VM sizes
- **Better Performance**: Switch to Standard_D4s_v3 or Standard_D8s_v3 nodes
- **High Availability**: Deploy across multiple availability zones

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Test your changes with `.\scripts\quick-deploy.ps1`
4. Commit your changes: `git commit -m 'Add amazing feature'`
5. Push to the branch: `git push origin feature/amazing-feature`
6. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🎯 Exhibition Tips

### Demo Success Factors

- ✅ **Test beforehand**: Deploy and verify everything works in your target region
- ✅ **Have backup plan**: Keep cleanup commands ready in case of issues
- ✅ **Engage audience**: Let them connect to the server and see their progress persist
- ✅ **Explain benefits**: Focus on business value, not just technical features
- ✅ **Time management**: Full deployment takes 15-20 minutes, have a pre-deployed instance ready

### Talking Points

- **Cost Efficiency**: Pay only for what you use with auto-scaling
- **Zero Downtime**: Demonstrate pod restart without service interruption
- **Enterprise Security**: Managed identities, network policies, and Azure security integration
- **Developer Experience**: From code to production in one command
- **Operational Excellence**: Built-in monitoring, logging, and alerting

---

**Ready to showcase cloud-native gaming infrastructure!** 🎮☁️
