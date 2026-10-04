#!/bin/bash
# Publishes a built disk image as a GitHub release: what the in-app updater
# offers and what the download link resolves to.
#
#   scripts/publish_release.sh [path/to/Ensembyte-1.0.0.dmg]
#
# The version is project.yml's MARKETING_VERSION; the disk image defaults to
# the one scripts/release.sh leaves in build.noindex. The notes come from
# ReleaseNotes/<version>.md, written as "## New features", "## Bug fixes" and
# "## Refinements" headings with a bullet per change: the app reads those
# three sections into its cards. Needs gh signed in.
set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT="soumyachk101/Ensembyte"
VERSION=$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"([^"]+)".*/\1/p' project.yml | head -1)
TAG="v$VERSION"
DMG="${1:-build.noindex/Ensembyte-$VERSION.dmg}"
NOTES="ReleaseNotes/$VERSION.md"

step() { printf '\n==> %s\n' "$1"; }

[ -f "$DMG" ] || { echo "No disk image at $DMG. Run scripts/release.sh first."; exit 1; }
[ -f "$NOTES" ] || { echo "No release notes at $NOTES."; exit 1; }
if ! grep -qE '^## (New features|Bug fixes|Refinements)' "$NOTES"; then
  echo "$NOTES needs at least one of the three headings: ## New features, ## Bug fixes, ## Refinements."
  exit 1
fi

step "Checking if the disk image is notarized"
if ! xcrun stapler validate "$DMG" > /dev/null 2>&1; then
  echo "Notice: $DMG is not stapled with an Apple notarization ticket. Proceeding."
fi

step "Tagging $TAG"
if ! git rev-parse -q --verify "refs/tags/$TAG" > /dev/null; then
  git tag -a "$TAG" -m "Ensembyte $VERSION"
fi

step "Creating the GitHub release"
if gh release view "$TAG" -R "$PROJECT" > /dev/null 2>&1; then
  echo "Release $TAG already exists on GitHub."
  exit 1
fi

UNVERSIONED_DMG="$(dirname "$DMG")/Ensembyte.dmg"
cp "$DMG" "$UNVERSIONED_DMG"

gh release create "$TAG" \
  "$DMG#Ensembyte $VERSION (Apple silicon)" \
  "$UNVERSIONED_DMG#Ensembyte (Apple silicon)" \
  -R "$PROJECT" \
  --title "Ensembyte $VERSION" \
  --notes-file "$NOTES"

printf '\nPublished: https://github.com/%s/releases/tag/%s\n' "$PROJECT" "$TAG"
