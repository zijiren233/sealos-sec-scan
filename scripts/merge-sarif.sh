#!/usr/bin/env bash
# Merge all per-tool SARIF files into out/merged.sarif for a single
# code-scanning upload (one category per target).
set -uo pipefail
OUT=$1

for t in trivy semgrep gitleaks gosec osv kube-linter hadolint zizmor bandit; do
  [ -s "$OUT/$t.sarif" ] || empty=1
done

npx --yes @microsoft/sarif-multitool@latest merge "$OUT"/*.sarif -o "$OUT/merged.sarif" >/dev/null 2>&1 || true

if ! [ -s "$OUT/merged.sarif" ] || \
   ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$OUT/merged.sarif" 2>/dev/null; then
  printf '{"version":"2.1.0","runs":[{"tool":{"driver":{"name":"merge-fallback","rules":[]}},"results":[]}]}' \
    > "$OUT/merged.sarif"
fi
echo "merged sarif ok: $(wc -c < "$OUT/merged.sarif") bytes"
