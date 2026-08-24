#!/usr/bin/env bash
# Release Helper Script for notetosms (Bash)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

NEW_VERSION="${1:-}"
PUSH=false

for arg in "$@"; do
  if [ "$arg" == "--push" ]; then
    PUSH=true
  fi
done

PUBSPEC_PATH="$PROJECT_ROOT/pubspec.yaml"
CURRENT_VERSION_LINE=$(grep "^version:" "$PUBSPEC_PATH")
CURRENT_VERSION=$(echo "$CURRENT_VERSION_LINE" | sed -E 's/version:[[:space:]]*([^+\r\n]+).*/\1/')
CURRENT_BUILD=$(echo "$CURRENT_VERSION_LINE" | grep -o '\+[0-9]*' | tr -d '+' || echo "1")

echo "======================================================"
echo "             notetosms Release Manager                "
echo "======================================================"
echo "Current Version: v$CURRENT_VERSION (Build $CURRENT_BUILD)"

if [ -z "$NEW_VERSION" ] || [ "$NEW_VERSION" == "--push" ]; then
  echo ""
  read -r -p "Target Version (e.g. 1.0.1, 1.1.0-beta.1): " INPUT_VER
  NEW_VERSION="${INPUT_VER#v}"
fi

NEW_BUILD=$((CURRENT_BUILD + 1))
TARGET_VERSION_STRING="$NEW_VERSION+$NEW_BUILD"
TAG_NAME="v$NEW_VERSION"

echo ""
echo "Target Version: $NEW_VERSION"
echo "Target Build  : $NEW_BUILD"
echo "Git Tag       : $TAG_NAME"
echo ""

# 1. Update pubspec.yaml
echo "[1/4] Updating pubspec.yaml..."
sed -i.bak -E "s/^version:.*/version: $TARGET_VERSION_STRING/" "$PUBSPEC_PATH"
rm -f "$PUBSPEC_PATH.bak"

# 2. Run static analysis
echo "[2/4] Running code quality validation..."
flutter analyze

# 3. Git commit & tag
echo "[3/4] Creating git commit and tag $TAG_NAME..."
git add pubspec.yaml
git commit -m "chore(release): bump version to $TAG_NAME"
git tag -a "$TAG_NAME" -m "Release $TAG_NAME"
echo "  -> Tag $TAG_NAME created."

# 4. Push
if [ "$PUSH" = true ]; then
  echo "[4/4] Pushing to origin..."
  git push origin main --tags
  echo "  -> Pushed! GitHub Actions workflow triggered."
else
  echo "[4/4] Release prepared locally."
  echo "To trigger GitHub Releases CI/CD, run:"
  echo "    git push origin main --tags"
fi

echo ""
echo "======================================================"
echo "           Release $TAG_NAME Ready!                   "
echo "======================================================"
