#!/usr/bin/env bash
# macOS packaging: build the release binary as a universal (arm64 + x86_64)
#   and produce:
#   target/package/orbit-<version>-macos-universal.dmg         (user download)
#   target/package/orbit-<version>-macos-universal-app.tar.gz  (auto-updater)
# containing Orbit.app (unsigned unless CODESIGN_IDENTITY is set).
#
# Usage: scripts/package-macos.sh
# Env:   CODESIGN_IDENTITY="Developer ID Application: …" to sign the bundle.
#        NOTARY_KEY_PATH + NOTARY_KEY_ID + NOTARY_ISSUER_ID — App Store Connect
#        API key (.p8) for notarization; all three set → notarize + staple the
#        app and the dmg, which removes the Gatekeeper warning entirely.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v cargo >/dev/null 2>&1 || PATH="$HOME/.cargo/bin:$PATH"
VERSION="$(grep -m1 '^version' "$ROOT/Cargo.toml" | sed 's/.*"\(.*\)".*/\1/')"
OUT_DIR="$ROOT/target/package"
APP="$OUT_DIR/Orbit.app"
DMG="$OUT_DIR/orbit-$VERSION-macos-universal.dmg"
APP_TARBALL="$OUT_DIR/orbit-$VERSION-macos-universal-app.tar.gz"

# Build a universal binary (arm64 + x86_64) via lipo so the DMG runs on
# every Intel and Apple Silicon Mac. Gatekeeper rejects a single-arch binary
# when the host doesn't match.
BUILD_DIR="$ROOT/target/package-build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

for TARGET in aarch64-apple-darwin x86_64-apple-darwin; do
  rustup target add "$TARGET" || true
  echo "building $TARGET..."
  cargo build --release -p orbit --target "$TARGET"
  cp "target/$TARGET/release/orbit" "$BUILD_DIR/orbit-$TARGET"
done

UNIVERSAL="$BUILD_DIR/orbit-universal"
lipo -create -output "$UNIVERSAL" \
  "$BUILD_DIR/orbit-aarch64-apple-darwin" \
  "$BUILD_DIR/orbit-x86_64-apple-darwin"

rm -rf "$APP" "$DMG" "$APP_TARBALL"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
install -m 755 "$UNIVERSAL" "$APP/Contents/MacOS/orbit"
rm -rf "$BUILD_DIR"
sed "s/__VERSION__/$VERSION/" "$ROOT/dist/macos/Info.plist" >"$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
mkdir -p "$APP/Contents/Resources/licenses/fonts"
cp "$ROOT/crates/ui/assets/fonts/licenses/"* "$APP/Contents/Resources/licenses/fonts/"

mkdir -p "$APP/Contents/Resources/licenses"
cp "$ROOT/crates/voice/NOTICE.md" "$APP/Contents/Resources/licenses"/parakeet-v3.txt

# Icon: iconset from the pre-masked macOS icon (squircle + margins + shadow
# baked into dist/macos/icon-1024.png — sips can't alpha-mask, so the mask is
# applied ahead of time; dist/orbit.png stays the full-bleed shared artwork).
ICONSET="$OUT_DIR/orbit.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ROOT/dist/macos/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" "$ROOT/dist/macos/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/orbit.icns"
rm -rf "$ICONSET"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  # Hardened runtime + secure timestamp are both notarization requirements.
  # (No --deep: Apple deprecated it; the bundle is a single Mach-O anyway.)
  codesign --entitlements "$ROOT/dist/macos/Dictation.entitlements" --force --options runtime --timestamp --identifier sh.orbit.app --sign "$CODESIGN_IDENTITY" "$APP"
else
  # Ad-hoc signature with canonical identifier so macOS recognizes the bundle
  codesign --force --deep --sign - --identifier sh.orbit.app "$APP"
fi

# notarize <path>: submit to Apple and wait for the verdict. A rejection may
# still exit 0 depending on the notarytool version — the `stapler staple` that
# follows each call has no ticket to attach then, and fails the build for us.
notarize() {
  xcrun notarytool submit "$1" \
    --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER_ID" --wait
}
NOTARIZE=false
[[ -n "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" ]] && NOTARIZE=true

if $NOTARIZE; then
  # Staple the bundle BEFORE tarring it: the auto-updater swaps the .app with
  # no dmg involved, so the tarball copy must carry its own ticket to pass
  # Gatekeeper offline.
  ZIP="$OUT_DIR/orbit-notarize.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  notarize "$ZIP"
  rm -f "$ZIP"
  xcrun stapler staple "$APP"
fi

# The auto-updater artifact.
tar -czf "$APP_TARBALL" -C "$OUT_DIR" Orbit.app
echo "packaged: $APP_TARBALL"

# Package the styled installer DMG.
# Stages the app + Applications symlink together with the pre-baked window
# styling from dist/macos (background, .DS_Store, volume icon), then builds
# a compressed UDZO image via a read-write intermediate so the volume root
# carries the custom-icon Finder flag.
VOLNAME="Orbit"
APP_BUNDLE_NAME="Orbit.app"
BACKGROUND_ASSET="$ROOT/dist/macos/installer-background.tiff"
DSSTORE_ASSET="$ROOT/dist/macos/installer-DS_Store.base64"
VOLUME_ICON_SOURCE="$APP/Contents/Resources/orbit.icns"

# Ensure no existing Orbit volume is mounted before staging
hdiutil detach "/Volumes/$VOLNAME"* -force -quiet >/dev/null 2>&1 || true

WORK_DIR="$(mktemp -d /tmp/orbit-dmg-XXXX)"
STAGE_PATH="$WORK_DIR/dmg-root"
DSSTORE_PATH="$WORK_DIR/DS_Store"
RW_DMG_PATH="$WORK_DIR/orbit-rw.dmg"
MOUNT_POINT="$WORK_DIR/mnt"

base64 -d < "$DSSTORE_ASSET" > "$DSSTORE_PATH" || { echo "Failed to decode $DSSTORE_ASSET" >&2; exit 1; }
LC_ALL=C grep -a -q -- "/Volumes/$VOLNAME" "$DSSTORE_PATH" \
  || { echo "The installer .DS_Store does not point its background at /Volumes/$VOLNAME" >&2; exit 1; }

mkdir -p "$STAGE_PATH"
ditto "$APP" "$STAGE_PATH/$APP_BUNDLE_NAME"
ln -s /Applications "$STAGE_PATH/Applications"
cp "$BACKGROUND_ASSET" "$STAGE_PATH/.background.tiff"
cp "$VOLUME_ICON_SOURCE" "$STAGE_PATH/.VolumeIcon.icns"

hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE_PATH" -ov -format UDRW -fs HFS+ "$RW_DMG_PATH" >/dev/null

mkdir -p "$MOUNT_POINT"
hdiutil attach "$RW_DMG_PATH" -nobrowse -noverify -mountpoint "$MOUNT_POINT" >/dev/null
cp "$DSSTORE_PATH" "$MOUNT_POINT/.DS_Store"

# Volume root FinderInfo: kHasCustomIcon = 0x0400
xattr -wx com.apple.FinderInfo \
  "00 00 00 00 00 00 00 00 04 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00" \
  "$MOUNT_POINT" || true

detached=0
for _ in 1 2 3 4 5; do
  if hdiutil detach "$MOUNT_POINT" -quiet >/dev/null 2>&1; then
    detached=1
    break
  fi
  sleep 1
done
if [ "$detached" -ne 1 ]; then
  hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 || true
fi

rm -f "$DMG"
hdiutil convert "$RW_DMG_PATH" -format UDZO -ov -o "$DMG" >/dev/null
rm -rf "$WORK_DIR"
if $NOTARIZE; then
  notarize "$DMG"
  xcrun stapler staple "$DMG"
fi
UNVERSIONED_DMG="$OUT_DIR/Orbit.dmg"
cp "$DMG" "$UNVERSIONED_DMG"
echo "packaged: $DMG"
echo "packaged: $UNVERSIONED_DMG"
