#!/bin/bash
set -e

# HAMi Docker Build and Push Script for GitHub Container Registry
# This script builds HAMi for AMD64 architecture and pushes to ghcr.io

# Configuration
REGISTRY="ghcr.io"
USERNAME="thuanpham582002"
IMAGE_NAME="hami"
VERSION="v2.5.1"
PLATFORM="linux/amd64"

# Full image name
FULL_IMAGE="${REGISTRY}/${USERNAME}/${IMAGE_NAME}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check if Docker is running
    if ! docker info &> /dev/null; then
        print_error "Docker is not running. Please start Docker first."
        exit 1
    fi
    
    # Check if buildx is available
    if ! docker buildx version &> /dev/null; then
        print_warning "Docker buildx not available. Installing..."
        docker buildx create --use --name multiarch
    fi
    
    # Check if authenticated with ghcr.io
    if ! docker info | grep -q "ghcr.io"; then
        print_warning "Not authenticated with ghcr.io. Please run:"
        print_warning "echo \$GITHUB_TOKEN | docker login ghcr.io -u ${USERNAME} --password-stdin"
        read -p "Press Enter to continue if you're already authenticated, or Ctrl+C to exit..."
    fi
    
    print_success "Prerequisites check completed"
}

# Function to display build information
display_build_info() {
    echo ""
    echo "=========================================="
    echo "HAMi Docker Build Configuration"
    echo "=========================================="
    echo "Registry: ${REGISTRY}"
    echo "Username: ${USERNAME}"
    echo "Image Name: ${IMAGE_NAME}"
    echo "Version: ${VERSION}"
    echo "Platform: ${PLATFORM}"
    echo "Full Image: ${FULL_IMAGE}"
    echo "Tags: ${VERSION}, latest"
    echo "=========================================="
    echo ""
}

# Function to build and push the image
build_and_push() {
    print_status "Starting Docker build process..."
    
    # Build arguments
    BUILD_ARGS=(
        "--platform" "${PLATFORM}"
        "--build-arg" "GOLANG_IMAGE=golang:1.22.5-bullseye"
        "--build-arg" "TARGET_ARCH=amd64"
        "--build-arg" "NVIDIA_IMAGE=nvidia/cuda:12.3.2-devel-ubuntu20.04"
        "--build-arg" "DEST_DIR=/usr/local/vgpu/"
        "--build-arg" "VERSION=${VERSION}"
        "--build-arg" "GOPROXY=https://goproxy.cn,direct"
        "-f" "docker/Dockerfile"
        "-t" "${FULL_IMAGE}:${VERSION}"
        "-t" "${FULL_IMAGE}:latest"
        "--push"
        "."
    )
    
    print_status "Building and pushing image with the following command:"
    echo "docker buildx build ${BUILD_ARGS[*]}"
    echo ""
    
    # Execute the build
    if docker buildx build "${BUILD_ARGS[@]}"; then
        print_success "Build and push completed successfully!"
    else
        print_error "Build failed!"
        exit 1
    fi
}

# Function to verify the build
verify_build() {
    print_status "Verifying the built image..."
    
    # Try to pull the image to verify it exists
    if docker pull "${FULL_IMAGE}:${VERSION}" &> /dev/null; then
        print_success "Image successfully available in registry"
        
        # Display image information
        print_status "Image information:"
        docker inspect "${FULL_IMAGE}:${VERSION}" --format='{{.Id}}' | head -c 12
        docker inspect "${FULL_IMAGE}:${VERSION}" --format='{{.Created}}'
        docker inspect "${FULL_IMAGE}:${VERSION}" --format='{{.Size}}' | numfmt --to=iec
        
    else
        print_error "Failed to verify image in registry"
        exit 1
    fi
}

# Function to display next steps
display_next_steps() {
    echo ""
    echo "=========================================="
    echo "Build Completed Successfully!"
    echo "=========================================="
    echo ""
    echo "Your HAMi images are now available at:"
    echo "  • ${FULL_IMAGE}:${VERSION}"
    echo "  • ${FULL_IMAGE}:latest"
    echo ""
    echo "Next steps:"
    echo "1. Deploy HAMi with Helm:"
    echo "   helm install hami ./charts/hami \\"
    echo "     -f charts/hami/production-values.yaml \\"
    echo "     -n kube-system \\"
    echo "     --set devicePlugin.image=${FULL_IMAGE}:${VERSION} \\"
    echo "     --set devicePlugin.monitorimage=${FULL_IMAGE}:${VERSION}"
    echo ""
    echo "2. Verify deployment:"
    echo "   kubectl get pods -n kube-system -l app=hami"
    echo ""
    echo "3. Test fractional GPU allocation in Kubeflow Jupyter"
    echo ""
    echo "=========================================="
}

# Main execution
main() {
    echo "HAMi Docker Build and Push Script"
    echo "================================="
    
    # Check if we're in the right directory
    if [[ ! -f "docker/Dockerfile" ]]; then
        print_error "Please run this script from the HAMi root directory"
        exit 1
    fi
    
    check_prerequisites
    display_build_info
    
    # Ask for confirmation
    read -p "Do you want to proceed with the build? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Build cancelled by user"
        exit 0
    fi
    
    build_and_push
    verify_build
    display_next_steps
}

# Run the main function
main "$@"
