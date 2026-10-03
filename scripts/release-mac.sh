#!/usr/bin/env bash
# release-mac.sh: Local native macOS release builder and publisher for Quorumly
# Builds Quorumly-swift, packages styled Quorumly.dmg, and publishes to GitHub Releases.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SWIFT_DIR="$ROOT_DIR/Quorumly-swift"
REPO="soumyachk101/Quorumly"

TAG="${1:-}"
if [ -z "$TAG" ]; then
    # Try latest git tag or default to v1.0.0
    TAG="$(git -C "$ROOT_DIR" describe --tags --abbrev=0 2>/dev/null || echo "v1.0.0")"
fi

VERSION="${TAG#v}"

echo "=================================================="
echo " Building Quorumly for macOS (Native Local Build)"
echo " Version: $VERSION (Tag: $TAG)"
echo " Repo:    $REPO"
echo "=================================================="

# Check requirements
command -v xcodebuild >/dev/null 2>&1 || { echo "Error: xcodebuild is required but not found." >&2; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "Error: GitHub CLI (gh) is required but not found." >&2; exit 1; }

cd "$SWIFT_DIR"

echo "==> Step 1: Compiling Quorumly (Release)..."
mkdir -p build.noindex
xcodebuild \
  -project Quorumly.xcodeproj \
  -scheme Quorumly \
  -configuration Release \
  -derivedDataPath build.noindex/DerivedData \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  build -quiet

APP_PATH="build.noindex/DerivedData/Build/Products/Release/Quorumly.app"
if [ ! -d "$APP_PATH" ]; then
    APP_PATH=$(find build.noindex/DerivedData -name "Quorumly.app" -type d | head -1)
fi

if [ ! -d "$APP_PATH" ]; then
    echo "Error: Quorumly.app was not produced by the build." >&2
    exit 1
fi
echo "✓ App bundle built at: $APP_PATH"

echo "==> Step 2: Packaging styled DMG..."
DMG_PATH="build.noindex/Quorumly.dmg"
VERSIONED_DMG_PATH="build.noindex/Quorumly-$VERSION.dmg"

./scripts/package_dmg.sh --app "$APP_PATH" --output "$DMG_PATH"
cp -f "$DMG_PATH" "$VERSIONED_DMG_PATH"
echo "✓ DMGs packaged successfully."

echo "==> Step 3: Uploading to GitHub Release ($TAG)..."
# Check if release exists; if not, create it
if ! gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "Creating new release $TAG on $REPO..."
    gh release create "$TAG" "$DMG_PATH" "$VERSIONED_DMG_PATH" \
      --repo "$REPO" \
      --title "$TAG" \
      --notes "Quorumly $TAG release"
else
    echo "Uploading DMG assets to existing release $TAG..."
    gh release upload "$TAG" "$DMG_PATH" "$VERSIONED_DMG_PATH" \
      --repo "$REPO" \
      --clobber
fi

echo "=================================================="
echo " macOS Release Successfully Published! 🚀"
echo " Downloads available at:"
echo " https://github.com/$REPO/releases/tag/$TAG"
echo "=================================================="
