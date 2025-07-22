# HAMi Docker Build and Deploy Guide

## Overview
This guide provides complete instructions for building and pushing HAMi GPU virtualization Docker images to GitHub Container Registry (ghcr.io) for AMD64 architecture.

## Prerequisites

### 1. Docker Setup
```bash
# Ensure Docker is installed and running
docker --version

# Enable Docker BuildKit for multi-platform builds
export DOCKER_BUILDKIT=1

# Install buildx if not available
docker buildx create --use --name multiarch
```

### 2. GitHub Container Registry Authentication
```bash
# Create a GitHub Personal Access Token with packages:write permission
# Then authenticate with ghcr.io
echo $GITHUB_TOKEN | docker login ghcr.io -u thuanpham582002 --password-stdin

# Verify authentication
docker info | grep -i registry
```

## Build Configuration

### Current HAMi Configuration
- **Version**: v2.5.1 (from VERSION file)
- **Target Registry**: ghcr.io/thuanpham582002/hami
- **Architecture**: linux/amd64
- **Base Images**: 
  - Build: golang:1.22.5-bullseye
  - Runtime: nvidia/cuda:12.6.3-base-ubuntu22.04

## Build Commands

### Option 1: Using HAMi Makefile (Recommended)

```bash
# Navigate to HAMi directory
cd HAMi

# Set environment variables for custom registry
export IMG_NAME=hami
export VERSION=v2.5.1
export IMG_TAG="ghcr.io/thuanpham582002/${IMG_NAME}:${VERSION}"

# Build the Docker image
make docker

# Also build with 'latest' tag
docker tag ghcr.io/thuanpham582002/hami:v2.5.1 ghcr.io/thuanpham582002/hami:latest
```

### Option 2: Direct Docker Build

```bash
# Navigate to HAMi directory
cd HAMi

# Build for AMD64 architecture
docker buildx build \
  --platform linux/amd64 \
  --build-arg GOLANG_IMAGE=golang:1.22.5-bullseye \
  --build-arg TARGET_ARCH=amd64 \
  --build-arg NVIDIA_IMAGE=nvidia/cuda:12.3.2-devel-ubuntu20.04 \
  --build-arg DEST_DIR=/usr/local/vgpu/ \
  --build-arg VERSION=v2.5.1 \
  --build-arg GOPROXY=https://goproxy.cn,direct \
  -f docker/Dockerfile \
  -t ghcr.io/thuanpham582002/hami:v2.5.1 \
  -t ghcr.io/thuanpham582002/hami:latest \
  --push \
  .
```

### Option 3: Multi-Architecture Build (if needed)

```bash
# Build for multiple architectures
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg GOLANG_IMAGE=golang:1.22.5-bullseye \
  --build-arg TARGET_ARCH=amd64 \
  --build-arg NVIDIA_IMAGE=nvidia/cuda:12.3.2-devel-ubuntu20.04 \
  --build-arg DEST_DIR=/usr/local/vgpu/ \
  --build-arg VERSION=v2.5.1 \
  --build-arg GOPROXY=https://goproxy.cn,direct \
  -f docker/Dockerfile \
  -t ghcr.io/thuanpham582002/hami:v2.5.1 \
  -t ghcr.io/thuanpham582002/hami:latest \
  --push \
  .
```

## Push Commands

```bash
# Push version-specific tag
docker push ghcr.io/thuanpham582002/hami:v2.5.1

# Push latest tag
docker push ghcr.io/thuanpham582002/hami:latest
```

## Verification

### 1. Verify Image in Registry
```bash
# Check if image exists in registry
docker pull ghcr.io/thuanpham582002/hami:v2.5.1

# Inspect the image
docker inspect ghcr.io/thuanpham582002/hami:v2.5.1
```

### 2. Test Image Locally
```bash
# Run a quick test to verify the image works
docker run --rm ghcr.io/thuanpham582002/hami:v2.5.1 nvidia-device-plugin --version
```

## Production Deployment

### 1. Update Helm Values
The production values are already configured in `charts/hami/production-values.yaml`:

```yaml
devicePlugin:
  image: "ghcr.io/thuanpham582002/hami"
  monitorimage: "ghcr.io/thuanpham582002/hami"
  imagePullPolicy: IfNotPresent
```

### 2. Deploy with Helm
```bash
# Deploy HAMi with custom image
helm install hami ./charts/hami \
  -f charts/hami/production-values.yaml \
  -n kube-system \
  --set devicePlugin.image=ghcr.io/thuanpham582002/hami:v2.5.1 \
  --set devicePlugin.monitorimage=ghcr.io/thuanpham582002/hami:v2.5.1
```

## Complete Build Script

Create `build-and-push.sh`:

```bash
#!/bin/bash
set -e

# Configuration
REGISTRY="ghcr.io"
USERNAME="thuanpham582002"
IMAGE_NAME="hami"
VERSION="v2.5.1"
PLATFORM="linux/amd64"

# Full image name
FULL_IMAGE="${REGISTRY}/${USERNAME}/${IMAGE_NAME}"

echo "Building HAMi Docker image..."
echo "Registry: ${REGISTRY}"
echo "Image: ${FULL_IMAGE}"
echo "Version: ${VERSION}"
echo "Platform: ${PLATFORM}"

# Navigate to HAMi directory
cd HAMi

# Build and push
docker buildx build \
  --platform ${PLATFORM} \
  --build-arg GOLANG_IMAGE=golang:1.22.5-bullseye \
  --build-arg TARGET_ARCH=amd64 \
  --build-arg NVIDIA_IMAGE=nvidia/cuda:12.3.2-devel-ubuntu20.04 \
  --build-arg DEST_DIR=/usr/local/vgpu/ \
  --build-arg VERSION=${VERSION} \
  --build-arg GOPROXY=https://goproxy.cn,direct \
  -f docker/Dockerfile \
  -t ${FULL_IMAGE}:${VERSION} \
  -t ${FULL_IMAGE}:latest \
  --push \
  .

echo "Build and push completed successfully!"
echo "Image available at: ${FULL_IMAGE}:${VERSION}"
echo "Image available at: ${FULL_IMAGE}:latest"
```

## Troubleshooting

### Common Issues

1. **Authentication Failed**
   ```bash
   # Re-authenticate with GitHub
   echo $GITHUB_TOKEN | docker login ghcr.io -u thuanpham582002 --password-stdin
   ```

2. **Build Context Too Large**
   ```bash
   # Use .dockerignore to exclude unnecessary files
   echo "*.git*" >> .dockerignore
   echo "docs/" >> .dockerignore
   echo "examples/" >> .dockerignore
   ```

3. **Platform Not Supported**
   ```bash
   # Ensure buildx is set up for multi-platform
   docker buildx ls
   docker buildx create --use --name multiarch
   ```

## Integration with Kubeflow

After building and pushing the image, it will work seamlessly with the Kubeflow Jupyter fractional GPU allocation fix, providing:

- **HAMi Device Plugin**: Recognizes fractional GPU resource requests
- **HAMi Scheduler**: Allocates appropriate GPU resources  
- **HAMi Core**: Enforces memory and compute limits at runtime
- **vGPU Monitor**: Provides GPU utilization metrics

The custom image ensures compatibility with your specific Kubeflow environment and the enhanced fractional GPU allocation capabilities.
