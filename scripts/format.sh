#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CLANG_FORMAT_BIN="${CLANG_FORMAT_BIN:-clang-format}"
REQUIRED_MAJOR=18

if ! command -v "$CLANG_FORMAT_BIN" >/dev/null 2>&1; then
  echo "ERROR: '$CLANG_FORMAT_BIN' not found." >&2
  exit 1
fi

# clang-format version >= 18 required
VERSION_STR="$("$CLANG_FORMAT_BIN" --version)"

ACTUAL_MAJOR="$(echo "$VERSION_STR" | grep -oE '[0-9]+' | head -n1)"

if [[ -z "$ACTUAL_MAJOR" ]]; then
  echo "ERROR: Failed to parse clang-format version: $VERSION_STR" >&2
  exit 1
fi

if (( ACTUAL_MAJOR < REQUIRED_MAJOR )); then
  echo "ERROR: clang-format >= $REQUIRED_MAJOR required, got $ACTUAL_MAJOR" >&2
  echo "Found: $VERSION_STR" >&2
  exit 1
fi

mapfile -t FILES < <(git ls-files \
  '*.c' '*.cc' '*.cpp' '*.cxx' \
  '*.h' '*.hh' '*.hpp' '*.hxx' \
  '*.inl' '*.tcc')

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "No C/C++ source files found to format."
  exit 0
fi

echo "Using: $VERSION_STR"
echo "Formatting ${#FILES[@]} files..."

"$CLANG_FORMAT_BIN" -i "${FILES[@]}"

echo "clang-format done."
