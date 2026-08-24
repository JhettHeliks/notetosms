#!/usr/bin/env bash
# Bash Build & Packaging Script for notetosms
set -euo pipefail

MODE="release"
SPLIT_PER_ABI=false
SKIP_CODEGEN=false
CLEAN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"
      shift 2
      ;;
    --beta)
      MODE="beta"
      shift
      ;;
    --release)
      MODE="release"
      shift
      ;;
    --split-per-abi)
      SPLIT_PER_ABI=true
      shift
      ;;
    --skip-codegen)
      SKIP_CODEGEN=true
      shift
      ;;
    --clean)
      CLEAN=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

echo "======================================================"
echo "       notetosms Build & Artifact Packaging"
echo "======================================================"
echo "Project Root: $PROJECT_ROOT"
echo "Build Mode  : $MODE"
echo "Split ABI   : $SPLIT_PER_ABI"
echo ""

if [ "$MODE" == "beta" ]; then
  DEST_DIR="$PROJECT_ROOT/dist/betas"
else
  DEST_DIR="$PROJECT_ROOT/dist/releases"
fi

mkdir -p "$DEST_DIR"

if [ "$CLEAN" = true ]; then
  echo "[1/4] Cleaning previous build artifacts..."
  flutter clean
fi

if [ "$SKIP_CODEGEN" = false ]; then
  echo "[2/4] Verifying Flutter Rust Bridge code generation..."
  if command -v flutter_rust_bridge_codegen &> /dev/null; then
    flutter_rust_bridge_codegen generate
    echo "  -> FRB code generation complete."
  else
    echo "  -> flutter_rust_bridge_codegen not in PATH, using committed bindings."
  fi
fi

echo "[3/4] Compiling Flutter APK ($MODE)..."
BUILD_ARGS=("build" "apk" "--$MODE")
if [ "$SPLIT_PER_ABI" = true ]; then
  BUILD_ARGS+=("--split-per-abi")
fi

flutter "${BUILD_ARGS[@]}"

echo "[4/4] Sorting and verifying outputs into $DEST_DIR..."
APK_SOURCE_DIR="$PROJECT_ROOT/build/app/outputs/flutter-apk"

for apk in "$APK_SOURCE_DIR"/*.apk; do
  if [ -f "$apk" ]; then
    filename=$(basename "$apk")
    target_file="$DEST_DIR/$filename"
    cp "$apk" "$target_file"

    if command -v sha256sum &> /dev/null; then
      sha256=$(sha256sum "$target_file" | awk '{print $1}')
      echo "$sha256  $filename" > "$target_file.sha256"
      echo "  -> Packaged: $filename (SHA256: ${sha256:0:16}...)"
    fi
  fi
done

echo ""
echo "======================================================"
echo "          Build & Packaging Succeeded!                "
echo "======================================================"
echo "Artifacts located in: $DEST_DIR"
