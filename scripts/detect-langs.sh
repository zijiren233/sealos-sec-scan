#!/usr/bin/env bash
# Emit CodeQL languages for a checked-out target.
# Go is deliberately excluded: CodeQL requires a successful build for Go
# (multi-module workspaces usually fail); Go coverage comes from gosec.
set -euo pipefail
SRC=$1
langs=()

if find "$SRC" -name package.json -not -path '*/node_modules/*' | grep -q .; then
  langs+=("javascript-typescript")
fi
if find "$SRC" -maxdepth 3 \( -name 'requirements*.txt' -o -name 'pyproject.toml' -o -name 'setup.py' \) | grep -q .; then
  langs+=("python")
fi

joined=$(IFS=,; echo "${langs[*]:-}")
echo "languages=$joined" >> "$GITHUB_OUTPUT"
echo "detected: ${joined:-none}"
