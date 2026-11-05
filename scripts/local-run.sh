#!/usr/bin/env bash
# Local reproduction of the CI tool suite against one working tree.
# Usage: scripts/local-run.sh /path/to/target-repo [output-dir]
set -uo pipefail
SRC=$(cd "$1" && pwd)
OUT=${2:-out}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$OUT"
cd "$ROOT" # semgrep reads .semgrepignore from the CWD

export PATH="$PATH:/usr/local/bin"

echo "==> semgrep"
command -v semgrep >/dev/null 2>&1 && semgrep scan \
  --config p/owasp-top-ten --config p/security-audit --config p/secrets \
  --config p/kubernetes --config p/dockerfile --config "$ROOT/semgrep-rules" \
  --sarif --metrics=off "$SRC" > "$OUT/semgrep.sarif" || true

echo "==> gitleaks"
command -v gitleaks >/dev/null 2>&1 && gitleaks detect --source "$SRC" --no-git --redact \
  --config "$ROOT/.gitleaks.toml" \
  --report-format sarif --report-path "$OUT/gitleaks.sarif" || true

echo "==> gosec"
if command -v gosec >/dev/null 2>&1; then
  i=0
  while IFS= read -r mod; do
    d="$(dirname "$mod")"; i=$((i+1))
    gosec -no-fail -exclude-generated -fmt sarif -out "$OUT/gosec-$i.sarif" "$d/..." || true
  done < <(find "$SRC" -name go.mod -not -path '*/vendor/*')
fi

echo "==> osv-scanner"
command -v osv-scanner >/dev/null 2>&1 && osv-scanner -r --format sarif --output "$OUT/osv.sarif" "$SRC" || true

echo "==> kube-linter"
command -v kube-linter >/dev/null 2>&1 && kube-linter lint "$SRC" --format sarif > "$OUT/kube-linter.sarif" || true

echo "==> hadolint"
command -v hadolint >/dev/null 2>&1 && \
  find "$SRC" -name 'Dockerfile*' -not -path '*/node_modules/*' -exec hadolint -f sarif {} + > "$OUT/hadolint.sarif" || true

echo "==> zizmor"
command -v zizmor >/dev/null 2>&1 && [ -d "$SRC/.github/workflows" ] && \
  zizmor --format sarif --no-online-audits "$SRC" > "$OUT/zizmor.sarif" || true

echo "==> bandit"
command -v bandit >/dev/null 2>&1 && find "$SRC" -name '*.py' -not -path '*/vendor/*' | grep -q . && \
  bandit -r -q -f sarif -o "$OUT/bandit.sarif" --exclude '*/test*,*/vendor/*' "$SRC" || true

echo "==> trivy"
command -v trivy >/dev/null 2>&1 && trivy fs --config "$ROOT/trivy.yaml" --format sarif --output "$OUT/trivy.sarif" "$SRC" || true

bash "$ROOT/scripts/merge-sarif.sh" "$OUT"
echo "done → $OUT/merged.sarif"
