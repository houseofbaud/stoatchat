#!/usr/bin/env bash

# Docker Build and Push Script
# ============================
# Builds Docker containers and optionally pushes them to a registry.
# This script is designed to be easy to edit by hand.

set -e  # Exit on error

# ============================================================================
# DEFAULT CONFIGURATION - Edit these values as needed
# ============================================================================

# Default registry (e.g., ghcr.io/myorg, docker.io/myuser)
# Leave empty for local-only builds
DEFAULT_REGISTRY=""

# Default tag for images (uses current date if not specified)
DEFAULT_TAG="$(date +%Y%m%d%M%S)"

# Default debug mode (true|false)
DEFAULT_DEBUG="false"

# Container definitions
# Format: "name:dockerfile_path"
# Edit this list to add/remove containers
CONTAINERS=(
    "base:Dockerfile.useCurrentArch"
    "server:crates/delta/Dockerfile"
    "bonfire:crates/bonfire/Dockerfile"
    "autumn:crates/services/autumn/Dockerfile"
    "january:crates/services/january/Dockerfile"
    "gifbox:crates/services/gifbox/Dockerfile"
    "crond:crates/daemons/crond/Dockerfile"
    "pushd:crates/daemons/pushd/Dockerfile"
    "voice-ingress:crates/daemons/voice-ingress/Dockerfile"
)

# Tag suffix when debug mode is enabled
DEBUG_TAG_SUFFIX="-debug"

# ============================================================================
# COMMAND LINE ARGUMENT PARSING
# ============================================================================

REGISTRY="${1:-$DEFAULT_REGISTRY}"
TAG="${2:-$DEFAULT_TAG}"
DEBUG="${3:-$DEFAULT_DEBUG}"

# ============================================================================
# FUNCTIONS
# ============================================================================

usage() {
    cat << EOF
Usage: $(basename "$0") [REGISTRY] [TAG] [DEBUG]

Builds Docker containers and optionally pushes them to a registry.

Arguments (all optional):
  REGISTRY  - Registry to push images to (default: "${DEFAULT_REGISTRY}")
              Examples: ghcr.io/myorg, docker.io/myuser
              Leave empty ("") for local-only builds
  TAG       - Tag for the images (default: ${DEFAULT_TAG})
  DEBUG     - Build with debug symbols: true|false (default: ${DEFAULT_DEBUG})

Examples:
  $(basename "$0")                                    # Local build with defaults
  $(basename "$0") ghcr.io/myorg                      # Push to registry with default tag
  $(basename "$0") ghcr.io/myorg v1.2.3               # Push with specific tag
  $(basename "$0") ghcr.io/myorg v1.2.3 true          # Debug build and push
  $(basename "$0") docker.io/user latest false        # Push to Docker Hub

Configuration:
  Edit default values at the top of this script.
  Edit CONTAINERS array to add/remove images to build.

EOF
    exit 0
}

# Show help
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    usage
fi

# ============================================================================
# MAIN SCRIPT
# ============================================================================

# Determine the final tag
FINAL_TAG="$TAG"
if [[ "$DEBUG" == "true" ]]; then
    FINAL_TAG="${TAG}${DEBUG_TAG_SUFFIX}"
fi

# Determine image prefix based on registry
if [[ -n "$REGISTRY" ]]; then
    IMAGE_PREFIX="${REGISTRY}/"
    echo "=========================================="
    echo "Building and pushing to registry"
    echo "=========================================="
    echo "Registry: $REGISTRY"
    echo "Tag:      $FINAL_TAG"
    echo "Debug:    $DEBUG"
    echo "=========================================="
else
    IMAGE_PREFIX=""
    echo "=========================================="
    echo "Building images locally (no push)"
    echo "=========================================="
    echo "Tag:      $FINAL_TAG"
    echo "Debug:    $DEBUG"
    echo "=========================================="
fi

# Enable debug symbols if requested
if [[ "$DEBUG" == "true" ]]; then
    echo ""
    echo "→ Enabling debug symbols in release build..."
    cat >> Cargo.toml << 'DEBUGEOF'
[profile.release]
debug = true
DEBUGEOF
fi

# Build all containers
echo ""
echo "Building containers..."
echo "----------------------------------------"

for container_def in "${CONTAINERS[@]}"; do
    # Parse container definition
    IFS=':' read -r name dockerfile <<< "$container_def"

    # Determine the tag for this container
    if [[ "$name" == "base" ]]; then
        # Base image always uses 'latest'
        image_tag="latest"
    else
        image_tag="$FINAL_TAG"
    fi

    # Build the image
    full_image_name="${IMAGE_PREFIX}${name}:${image_tag}"
    echo ""
    echo "Building: $full_image_name"

    if [[ "$name" == "base" ]]; then
        # Base image uses root context
        docker build -t "$full_image_name" -f "$dockerfile" .
    else
        # Other images use their Dockerfile as stdin
        docker build -t "$full_image_name" - < "$dockerfile"
    fi

    echo "✓ Built: $full_image_name"
done

# Restore Cargo.toml if modified
if [[ "$DEBUG" == "true" ]]; then
    echo ""
    echo "→ Restoring Cargo.toml..."
    git restore Cargo.toml
fi

# Push images if registry was specified
if [[ -n "$REGISTRY" ]]; then
    echo ""
    echo "Pushing images to registry..."
    echo "----------------------------------------"

    for container_def in "${CONTAINERS[@]}"; do
        IFS=':' read -r name dockerfile <<< "$container_def"

        # Determine tag
        if [[ "$name" == "base" ]]; then
            image_tag="latest"
        else
            image_tag="$FINAL_TAG"
        fi

        full_image_name="${IMAGE_PREFIX}${name}:${image_tag}"
        echo ""
        echo "Pushing: $full_image_name"
        docker push "$full_image_name"
        echo "✓ Pushed: $full_image_name"
    done

    echo ""
    echo "=========================================="
    echo "✓ All images built and pushed successfully!"
    echo "=========================================="
else
    echo ""
    echo "=========================================="
    echo "✓ All images built locally!"
    echo "=========================================="
    echo ""
    echo "To push to a registry, run:"
    echo "  $(basename "$0") ghcr.io/myorg $TAG $DEBUG"
    echo "=========================================="
fi

