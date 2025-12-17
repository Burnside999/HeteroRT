#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CLANG_TIDY_BIN="${CLANG_TIDY_BIN:-clang-tidy}"
REQUIRED_MAJOR=18

if ! command -v "$CLANG_TIDY_BIN" >/dev/null 2>&1; then
  echo "ERROR: '$CLANG_TIDY_BIN' not found." >&2
  exit 1
fi

# clang-tidy version >= 18 required
VERSION_STR="$("$CLANG_TIDY_BIN" --version)"
ACTUAL_MAJOR="$(echo "$VERSION_STR" | grep -oE '[0-9]+' | head -n1)"

if [[ -z "$ACTUAL_MAJOR" ]]; then
  echo "ERROR: Failed to parse clang-tidy version: $VERSION_STR" >&2
  exit 1
fi

if (( ACTUAL_MAJOR < REQUIRED_MAJOR )); then
  echo "ERROR: clang-tidy >= $REQUIRED_MAJOR required, got $ACTUAL_MAJOR" >&2
  echo "Found: $VERSION_STR" >&2
  exit 1
fi

BUILD_DIR="${1:-build}"
shift || true

JOBS=""
if [[ "${1:-}" == "-j" ]]; then
  JOBS="${2:-}"
  shift 2 || true
fi
if [[ -z "$JOBS" ]]; then
  JOBS="$(command -v nproc >/dev/null 2>&1 && nproc || echo 4)"
fi

COMPDB="$BUILD_DIR/compile_commands.json"
if [[ ! -f "$COMPDB" ]]; then
  echo "ERROR: '$COMPDB' not found." >&2
  echo "Hint: cmake -S . -B $BUILD_DIR -DCMAKE_EXPORT_COMPILE_COMMANDS=ON" >&2
  exit 1
fi

mapfile -t FILES < <(git ls-files \
  '*.c' '*.cc' '*.cpp' '*.cxx' \
  '*.h' '*.hh' '*.hpp' '*.hxx' \
  '*.inl' '*.tcc')

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "No C/C++ source files found to lint."
  exit 0
fi

echo "Using: $VERSION_STR"
echo "Linting ${#FILES[@]} files (jobs=$JOBS)..."

"$CLANG_TIDY_BIN" \
  -p "$BUILD_DIR" \
  --quiet \
  -j "$JOBS" \
  "${FILES[@]}"

echo "clang-tidy done."
