# 🎮 Exhibition Demo Guide: Pod Restart Resilience

## Overview

This guide demonstrates how Kubernetes maintains service availability and IP consistency even when pods fail or restart while players are actively connected to the Minecraft server. This showcases enterprise-grade reliability patterns in a fun, interactive way.

## Prerequisites

- ✅ Deployed Minecraft AKS cluster using `scripts/quick-deploy.ps1`
- ✅ External IP assigned and accessible: `40.127.222.166:25565`
- ✅ At least one player connected to the server
- ✅ kubectl configured and connected to the cluster

## Demo Scenario: "Resilient Gaming Experience"

### Phase 1: Establish Baseline

**Audience Message**: *"Let's start by showing our running Minecraft server and establishing a baseline."*

1. **Show Current Status**

   ```powershell
   # Display service information
   kubectl get service minecraft-service -o wide

   # Show current pod
   kubectl get pods -l app=minecraft-server -o wide

   # Test connectivity
   Test-NetConnection -ComputerName 40.127.222.166 -Port 25565
   ```

2. **Connect Players** (If available)
   - Have someone connect to `40.127.222.166:25565`
   - Show active player in server logs:

   ```powershell
   kubectl logs -l app=minecraft-server --tail=10
   ```

3. **Record Initial State**

   ```powershell
   # Record current pod name
   $initialPod = kubectl get pods -l app=minecraft-server -o jsonpath='{.items[0].metadata.name}'
   Write-Host "Initial Pod: $initialPod" -ForegroundColor Green

   # Record external IP
   $externalIP = kubectl get service minecraft-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
   Write-Host "External IP: $externalIP" -ForegroundColor Green
   ```

### Phase 2: Simulate Pod Failure

**Audience Message**: *"Now let's simulate a pod failure - this could happen due to hardware issues, node maintenance, or resource constraints."*

1. **Monitor in Real-Time** (Optional: Second Terminal)

   ```powershell
   # In separate terminal - watch pod status
   kubectl get pods -l app=minecraft-server -w
   ```

2. **Simulate Failure**

   ```powershell
   # Delete the pod to simulate failure
   Write-Host "🔥 Simulating pod failure..." -ForegroundColor Red
   kubectl delete pod -l app=minecraft-server

   Write-Host "Pod deleted! Kubernetes will automatically create a new one..." -ForegroundColor Yellow
   ```

3. **Show Kubernetes Response**

   ```powershell
   # Watch the replacement happen
   kubectl get pods -l app=minecraft-server

   # Wait for rollout to complete
   kubectl rollout status deployment/minecraft-server --timeout=300s
   ```

### Phase 3: Verify Consistency

**Audience Message**: *"The magic of Kubernetes - let's verify that our service remained consistent."*

1. **Compare Pod Names**

   ```powershell
   # Get new pod name
   $newPod = kubectl get pods -l app=minecraft-server -o jsonpath='{.items[0].metadata.name}'
   Write-Host "Original Pod: $initialPod" -ForegroundColor Cyan
   Write-Host "New Pod: $newPod" -ForegroundColor Green
   Write-Host "✅ Different pod = successful replacement" -ForegroundColor Green
   ```

2. **Verify IP Consistency**

   ```powershell
   # Check if IP remained the same
   $newIP = kubectl get service minecraft-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
   Write-Host "Original IP: $externalIP" -ForegroundColor Cyan
   Write-Host "Current IP: $newIP" -ForegroundColor Green

   if ($newIP -eq $externalIP) {
       Write-Host "🎉 IP CONSISTENCY MAINTAINED!" -ForegroundColor Green
   } else {
       Write-Host "❌ IP Changed (This shouldn't happen)" -ForegroundColor Red
   }
   ```

3. **Test Connectivity**

   ```powershell
   # Verify server is accessible
   Test-NetConnection -ComputerName $newIP -Port 25565

   # Check server logs for startup
   kubectl logs -l app=minecraft-server --tail=20
   ```

### Phase 4: Data Persistence Verification

**Audience Message**: *"Let's verify that player progress and world data survived the pod restart."*

1. **Check World Data Persistence**

   ```powershell
   # Show persistent volume status
   kubectl get pvc minecraft-pvc

   # Show that the same volume is mounted
   kubectl describe pod -l app=minecraft-server | Select-String -Pattern "Volume|Mount"
   ```

2. **Player Reconnection** (If applicable)
   - Have the player reconnect to the same IP
   - Show that their progress/world changes are intact
   - Display server logs showing successful reconnection

### Phase 5: Advanced Demonstrations

#### Multiple Failure Simulation

**Audience Message**: *"Let's stress test this by failing the pod multiple times rapidly."*

```powershell
# Run our automated consistency test
.\scripts\test-ip-consistency.ps1
```

#### Real-Time Monitoring

**Audience Message**: *"In production, you'd want to monitor this. Let's see what that looks like."*

```powershell
# Show service status
kubectl get service minecraft-service

# Show deployment health
kubectl get deployment minecraft-server

# Show pod distribution across nodes
kubectl get pods -l app=minecraft-server -o wide
```

## Talking Points for Exhibition

### Technical Benefits

- **Zero Configuration**: LoadBalancer service automatically provides stable IP
- **Automatic Recovery**: Kubernetes replaces failed pods without manual intervention
- **Data Persistence**: Azure Files ensures world data survives pod restarts
- **Horizontal Scaling**: Can easily scale to multiple pods for load distribution

### Business Benefits

- **High Availability**: 99.9% uptime even with infrastructure failures
- **Predictable Costs**: Azure managed services with transparent pricing
- **Operational Simplicity**: Minimal maintenance overhead
- **Disaster Recovery**: Built-in resilience patterns

### Enterprise Patterns Demonstrated

- **Immutable Infrastructure**: Pods are cattle, not pets
- **Service Discovery**: Consistent endpoints regardless of backend changes
- **Health Monitoring**: Kubernetes automatically detects and replaces unhealthy pods
- **Resource Management**: Guaranteed CPU/memory allocation with limits

## Common Questions & Answers

**Q: "What happens to connected players during pod restart?"**
A: Players will disconnect briefly (30-60 seconds) but can reconnect to the same IP immediately. Their world progress is preserved.

**Q: "How long does pod restart take?"**
A: Typically 30-60 seconds. Kubernetes detects failure quickly and starts replacement immediately.

**Q: "What if the entire node fails?"**
A: Kubernetes reschedules the pod to a healthy node. Same IP, same data, different infrastructure.

**Q: "Can this scale to handle more players?"**
A: Yes! Increase replica count in deployment or use horizontal pod autoscaling based on CPU/memory.

**Q: "What about backups?"**
A: Azure Files provides built-in redundancy. You can also implement automated backup strategies.

## Troubleshooting During Demo

### If External IP Takes Too Long

```powershell
# Check LoadBalancer provisioning
kubectl describe service minecraft-service

# Check for quota issues
az vm list-usage --location northeurope --query "[?name.value=='Total Regional vCPUs']"
```

### If Pod Won't Start

```powershell
# Check pod status
kubectl describe pod -l app=minecraft-server

# Check events
kubectl get events --sort-by='.lastTimestamp'

# Check storage mounting
kubectl describe pvc minecraft-pvc
```

### If Connectivity Fails

```powershell
# Verify network security groups
kubectl get service minecraft-service -o yaml

# Test internal connectivity
kubectl run test-pod --image=busybox --rm -it -- nc -zv minecraft-service 25565
```

## Demo Script Variations

### Quick Demo (5 minutes)

1. Show running server
2. Delete pod
3. Show new pod with same IP
4. Test connectivity

### Technical Deep Dive (15 minutes)

1. Explain architecture
2. Show monitoring tools
3. Multiple failure simulation
4. Scaling demonstration
5. Storage persistence verification

### Business-Focused (10 minutes)

1. Cost comparison with traditional hosting
2. Reliability guarantees
3. Operational benefits
4. Security and compliance features

## Success Metrics

- ✅ Pod restart completes in under 60 seconds
- ✅ External IP remains consistent across all restarts
- ✅ Zero data loss demonstrated
- ✅ Audience understands cloud-native benefits
- ✅ Questions answered confidently

---

## Ready-to-Use Commands Cheat Sheet

```powershell
# Quick status check
kubectl get all -l app=minecraft-server

# Simulate failure
kubectl delete pod -l app=minecraft-server

# Watch recovery
kubectl get pods -l app=minecraft-server -w

# Verify IP consistency
kubectl get service minecraft-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Test connectivity
Test-NetConnection -ComputerName 40.127.222.166 -Port 25565

# Run full consistency test
.\scripts\test-ip-consistency.ps1

# Show logs
kubectl logs -l app=minecraft-server --tail=20 -f

# Cleanup after demo
az group delete --name rg-demo01-minecraft-aks-demo --yes --no-wait
```

This demonstration perfectly showcases how modern cloud-native applications provide enterprise-grade reliability while maintaining simplicity for developers and operators.
