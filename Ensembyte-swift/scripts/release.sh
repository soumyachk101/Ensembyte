#!/bin/bash
# Builds, signs, notarizes and packages Ensembyte as one disk image per architecture.
#
#   scripts/release.sh            # Apple silicon (arm64), then Intel (x86_64)
#   scripts/release.sh x86_64     # only the architectures named
#
# Each architecture is its own single-architecture build with its own disk image, so
# neither download carries the other's code. Needs Xcode, XcodeGen, a Developer ID
# Application certificate for the team below and a notarytool keychain profile
# (NOTARY_PROFILE, "Ensembyte-Notarize" by default). SwiftTerm's build plugin runs a tool built
# for the architecture being built, so the Mac must be able to run that architecture: an
# Apple silicon Mac builds both (Intel needs Rosetta), an Intel Mac only Intel.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
TEAM_ID="NARHG44L48"
NOTARY_PROFILE="${NOTARY_PROFILE:-Ensembyte-Notarize}"
APP_NAME="Ensembyte"
# ".noindex" keeps Spotlight and Launchpad from listing the build copies of the app.
BUILD="$ROOT/build.noindex"
VERSION=$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"([^"]+)".*/\1/p' project.yml | head -1)

step() { printf '
==> %s
' "$1"; }

# What an architecture is called to people; publish_release.sh carries the same names.
label_for() {
  case "$1" in
    arm64) echo "Apple silicon" ;;
    x86_64) echo "Intel" ;;
  esac
}

if [ $# -gt 0 ]; then TARGETS=("$@"); else TARGETS=(arm64 x86_64); fi
for arch in "${TARGETS[@]}"; do
  [ -n "$(label_for "$arch")" ] || { echo "Unknown architecture: $arch (use arm64 or x86_64)"; exit 1; }
done

notarize() {
  local file="$1" result status id
  result=$(xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)
  status=$(printf '%s' "$result" | plutil -extract status raw - 2>/dev/null || true)
  if [ "$status" != "Accepted" ]; then
    printf '%s
' "$result"
    id=$(printf '%s' "$result" | plutil -extract id raw - 2>/dev/null || true)
    [ -n "$id" ] && xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE"
    exit 1
  fi
  echo "Notarization accepted for $(basename "$file")"
}

step "Generating the Xcode project"
xcodegen generate --quiet
mkdir -p "$BUILD"

# Everything for one architecture lives under $BUILD/<arch>; only its disk image stays in
# $BUILD, next to the other architecture's.
release_arch() {
  local arch="$1" label work archive exported app details archs identity dmg
  label=$(label_for "$arch")
  work="$BUILD/$arch"
  archive="$work/$APP_NAME.xcarchive"
  exported="$work/export"
  dmg="$BUILD/$APP_NAME-$VERSION-$arch.dmg"

  step "Archiving $APP_NAME $VERSION for $label ($arch)"
  rm -rf "$work" "$dmg"
  mkdir -p "$work"
  if ! xcodebuild archive     -project Ensembyte.xcodeproj     -scheme Ensembyte     -configuration Release     -destination 'generic/platform=macOS'     -archivePath "$archive"     -derivedDataPath "$work/DerivedData"     -skipPackagePluginValidation     -skipMacroValidation     ARCHS="$arch"     ONLY_ACTIVE_ARCH=NO > "$work/archive.log" 2>&1; then
    grep -E "error:" "$work/archive.log" | head -40 || tail -40 "$work/archive.log"
    exit 1
  fi

  step "Exporting with Developer ID ($label)"
  cat > "$work/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>signingCertificate</key>
  <string>Developer ID Application</string>
</dict>
</plist>
PLIST
  if ! xcodebuild -exportArchive     -archivePath "$archive"     -exportPath "$exported"     -exportOptionsPlist "$work/ExportOptions.plist" > "$work/export.log" 2>&1; then
    tail -40 "$work/export.log"
    exit 1
  fi
  app="$exported/$APP_NAME.app"

  step "Verifying the signature ($label)"
  codesign --verify --deep --strict --verbose=2 "$app"
  details=$(codesign -dv --verbose=4 "$app" 2>&1)
  grep -q "Authority=Developer ID Application" <<< "$details"
  grep -q "flags=.*runtime" <<< "$details"
  grep -q "Timestamp=" <<< "$details"
  archs=$(lipo -archs "$app/Contents/MacOS/$APP_NAME")
  if [ "$archs" != "$arch" ]; then
    echo "Expected the $label build ($arch), got: $archs"
    exit 1
  fi

  step "Notarizing the app ($label)"
  ditto -c -k --keepParent "$app" "$work/$APP_NAME.zip"
  notarize "$work/$APP_NAME.zip"
  xcrun stapler staple "$app"

  step "Building the disk image ($label)"
  "$ROOT/scripts/package_dmg.sh" --app "$app" --output "$dmg"
  identity=$(security find-identity -v -p codesigning | sed -nE "s/.*\"(Developer ID Application: .*\(\$TEAM_ID\))\".*/\1/p" | head -1)
  codesign --sign "$identity" --timestamp "$dmg"

  step "Notarizing the disk image ($label)"
  notarize "$dmg"
  xcrun stapler staple "$dmg"

  step "Checking Gatekeeper ($label)"
  spctl --assess --type execute --ignore-cache --no-cache --verbose "$app"
  spctl --assess --type open --context context:primary-signature --ignore-cache --no-cache --verbose "$dmg"
  xcrun stapler validate "$dmg"

  # Also provide universal/default name for arm64
  if [ "$arch" = "arm64" ]; then
    cp -f "$dmg" "$BUILD/$APP_NAME-$VERSION.dmg"
  fi

  step "Cleaning up ($label)"
  # Only the disk image stays, so Spotlight and Launchpad never list a second copy of the app.
  rm -rf "$archive" "$exported" "$work/$APP_NAME.zip" "$work/DerivedData"
}

for arch in "${TARGETS[@]}"; do
  release_arch "$arch"
done

printf '
Ready:
'
for arch in "${TARGETS[@]}"; do
  printf '  %s
' "$BUILD/$APP_NAME-$VERSION-$arch.dmg"
done
printf 'Publish them with scripts/publish_release.sh once architectures are built.
'
