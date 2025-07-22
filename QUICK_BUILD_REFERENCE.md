# HAMi Docker Build - Quick Reference

## Prerequisites Setup

### 1. GitHub Authentication
```bash
# Create GitHub Personal Access Token with packages:write permission
# Then authenticate:
export GITHUB_TOKEN="your_github_token_here"
echo $GITHUB_TOKEN | docker login ghcr.io -u thuanpham582002 --password-stdin
```

### 2. Docker BuildKit Setup
```bash
# Enable BuildKit and create builder
export DOCKER_BUILDKIT=1
docker buildx create --use --name multiarch
```

## Quick Build Commands

### Option 1: Use the Automated Script (Recommended)
```bash
cd HAMi
./build-and-push.sh
```

### Option 2: Manual Build with Makefile
```bash
cd HAMi
export IMG_TAG="ghcr.io/thuanpham582002/hami:v2.5.1"
make docker
docker tag ghcr.io/thuanpham582002/hami:v2.5.1 ghcr.io/thuanpham582002/hami:latest
docker push ghcr.io/thuanpham582002/hami:v2.5.1
docker push ghcr.io/thuanpham582002/hami:latest
```

### Option 3: Direct Docker Build
```bash
cd HAMi
docker buildx build \
  --platform linux/amd64 \
  --build-arg VERSION=v2.5.1 \
  -f docker/Dockerfile \
  -t ghcr.io/thuanpham582002/hami:v2.5.1 \
  -t ghcr.io/thuanpham582002/hami:latest \
  --push \
  .
```

## Deployment Commands

### Deploy with Helm
```bash
# Using production values (already configured for ghcr.io/thuanpham582002/hami)
helm install hami ./charts/hami \
  -f charts/hami/production-values.yaml \
  -n kube-system

# Or specify exact version
helm install hami ./charts/hami \
  -f charts/hami/production-values.yaml \
  -n kube-system \
  --set devicePlugin.image=ghcr.io/thuanpham582002/hami:v2.5.1 \
  --set devicePlugin.monitorimage=ghcr.io/thuanpham582002/hami:v2.5.1
```

### Verify Deployment
```bash
# Check HAMi pods
kubectl get pods -n kube-system -l app=hami

# Check device plugin logs
kubectl logs -n kube-system -l app=hami-device-plugin

# Check scheduler logs  
kubectl logs -n kube-system -l app=hami-scheduler
```

## Verification Commands

### Test Image
```bash
# Pull and inspect
docker pull ghcr.io/thuanpham582002/hami:v2.5.1
docker inspect ghcr.io/thuanpham582002/hami:v2.5.1

# Test run
docker run --rm ghcr.io/thuanpham582002/hami:v2.5.1 nvidia-device-plugin --version
```

### Test Fractional GPU in Kubeflow
```bash
# Create test notebook with fractional GPU
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-fractional-gpu
spec:
  containers:
  - name: notebook
    image: jupyter/tensorflow-notebook
    resources:
      limits:
        nvidia.com/gpu: "1"
        nvidia.com/gpucores: "50"
        nvidia.com/gpumem-percentage: "50"
EOF

# Check resource allocation
kubectl describe pod test-fractional-gpu
```

## Troubleshooting

### Authentication Issues
```bash
# Re-authenticate
docker logout ghcr.io
echo $GITHUB_TOKEN | docker login ghcr.io -u thuanpham582002 --password-stdin
```

### Build Issues
```bash
# Clean Docker cache
docker system prune -a

# Rebuild buildx
docker buildx rm multiarch
docker buildx create --use --name multiarch
```

### Registry Issues
```bash
# Check if image exists
curl -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://ghcr.io/v2/thuanpham582002/hami/tags/list
```

## File Locations

- **Build Script**: `HAMi/build-and-push.sh`
- **Dockerfile**: `HAMi/docker/Dockerfile`
- **Production Values**: `HAMi/charts/hami/production-values.yaml`
- **Version**: `HAMi/VERSION` (v2.5.1)

## Expected Results

After successful build and deployment:

1. **Images Available**:
   - `ghcr.io/thuanpham582002/hami:v2.5.1`
   - `ghcr.io/thuanpham582002/hami:latest`

2. **HAMi Components Running**:
   - Device Plugin pods on GPU nodes
   - Scheduler pod
   - Monitor pods

3. **Fractional GPU Support**:
   - Kubeflow Jupyter can request fractional GPUs
   - HAMi enforces resource limits
   - Multiple workloads can share GPUs

## Integration with Kubeflow Fix

This HAMi image works with the Kubeflow Jupyter fractional GPU fix:

- **Frontend**: Users select fractional GPU in Jupyter spawner UI
- **Backend**: Kubeflow generates HAMi resource specifications
- **HAMi**: This image enforces the fractional allocations

The complete pipeline enables true GPU sharing in Kubeflow environments.
