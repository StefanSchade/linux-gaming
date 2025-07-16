#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <root-directory>"
  exit 1
fi

ROOT_DIR="$1"

find "$ROOT_DIR" -type f | while read -r FILE; do
  if iconv -f UTF-8 -t UTF-8 "$FILE" -o /dev/null 2>/dev/null; then
    REL_PATH="${FILE#$ROOT_DIR/}"
    SIZE=$(stat --printf="%s" "$FILE")
    MTIME=$(stat --printf="%y" "$FILE")
    echo "===== FILE: $REL_PATH ====="
    echo "Size: $SIZE bytes"
    echo "Modified: $MTIME"
    echo "----------------------------------------"
    cat "$FILE"
    echo -e "\n===== END OF: $REL_PATH =====\n"
  else
    echo "Skipping non-UTF8 file: ${FILE#$ROOT_DIR/}" >&2
  fi
done

