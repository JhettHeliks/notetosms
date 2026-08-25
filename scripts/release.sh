#!/usr/bin/env bash
# Automated Release Script for notetosms
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <version> [release_notes] (e.g. $0 1.0.1 \"UI updates and bugfixes\")"
  exit 1
fi

INPUT_VERSION="$1"
RELEASE_NOTES_ARG="${2:-}"

# Strip any leading 'v'
VERSION="${INPUT_VERSION#v}"
TAG_NAME="v$VERSION"
PUBSPEC_PATH="$PROJECT_ROOT/pubspec.yaml"
RELEASE_NOTES_FILE="$PROJECT_ROOT/RELEASE_NOTES.md"

if [ ! -f "$PUBSPEC_PATH" ]; then
  echo "Error: pubspec.yaml not found at $PUBSPEC_PATH"
  exit 1
fi

# Determine Release Notes: argument takes precedence, then RELEASE_NOTES.md
RELEASE_NOTES=""
if [ -n "$RELEASE_NOTES_ARG" ]; then
  RELEASE_NOTES="$RELEASE_NOTES_ARG"
elif [ -f "$RELEASE_NOTES_FILE" ] && [ -s "$RELEASE_NOTES_FILE" ]; then
  RELEASE_NOTES=$(cat "$RELEASE_NOTES_FILE")
fi

# Extract current build number if present, otherwise default to 1
CURRENT_VERSION_LINE=$(grep "^version:" "$PUBSPEC_PATH")
CURRENT_BUILD=$(echo "$CURRENT_VERSION_LINE" | grep -o '\+[0-9]*' | tr -d '+' || echo "")
if [ -z "$CURRENT_BUILD" ]; then
  NEW_BUILD=1
else
  NEW_BUILD=$((CURRENT_BUILD + 1))
fi

TARGET_VERSION_STRING="$VERSION+$NEW_BUILD"

echo "======================================================"
echo "          notetosms Release Automation Pipeline       "
echo "======================================================"
echo "Target Version : $VERSION"
echo "Build Number   : $NEW_BUILD"
echo "Git Tag        : $TAG_NAME"
if [ -n "$RELEASE_NOTES" ]; then
  echo "Release Notes  : Provided"
fi
echo "======================================================"
echo ""

# 1. Update version in pubspec.yaml
echo "[1/5] Updating pubspec.yaml to version: $TARGET_VERSION_STRING..."
sed -i.bak -E "s/^version:[[:space:]]*.*/version: $TARGET_VERSION_STRING/" "$PUBSPEC_PATH"
rm -f "$PUBSPEC_PATH.bak"

# 2. Run static analysis
echo "[2/5] Running static analysis check..."
flutter analyze lib/ --no-pub

# 3. Stage changes
echo "[3/5] Staging pubspec.yaml and release assets..."
git add pubspec.yaml
if [ -f "$RELEASE_NOTES_FILE" ]; then
  git add "$RELEASE_NOTES_FILE"
fi

# 4. Commit and Tag
echo "[4/5] Creating commit and tag $TAG_NAME..."
git commit -m "chore(release): bump version to $TAG_NAME"

if [ -n "$RELEASE_NOTES" ]; then
  git tag -f -a "$TAG_NAME" -m "Release $TAG_NAME" -m "$RELEASE_NOTES"
else
  git tag -f -a "$TAG_NAME" -m "Release $TAG_NAME"
fi

# 5. Push branch and tag to origin
echo "[5/5] Pushing to origin..."
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
git push origin "$CURRENT_BRANCH"
git push -f origin "$TAG_NAME"

echo ""
echo "======================================================"
echo "  Successfully released $TAG_NAME and pushed to GitHub! "
echo "  GitHub Actions CI/CD release workflow is now running. "
echo "======================================================"
