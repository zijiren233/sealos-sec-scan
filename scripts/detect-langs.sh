#!/usr/bin/env bash
# Emit CodeQL languages for a checked-out target.
set -euo pipefail
SRC=$1
langs=()

if find "$SRC" -name package.json -not -path '*/node_modules/*' | grep -q .; then
  langs+=("javascript-typescript")
fi
if find "$SRC" -name go.mod -not -path '*/vendor/*' | grep -q .; then
  langs+=("go")
fi
if find "$SRC" -maxdepth 3 \( -name 'requirements*.txt' -o -name 'pyproject.toml' -o -name 'setup.py' \) | grep -q .; then
  langs+=("python")
fi

joined=$(IFS=,; echo "${langs[*]:-}")
echo "languages=$joined" >> "$GITHUB_OUTPUT"
echo "detected: ${joined:-none}"
