#!/usr/bin/env bash
# CLI tool suite: semgrep, gitleaks, gosec, osv-scanner, kube-linter,
# hadolint, zizmor, bandit. Each tool is guarded: missing binary, absent
# language or scanner error never fails the job, and every expected SARIF
# file always exists afterwards (valid empty document when nothing ran).
set -uo pipefail
SRC=$1
OUT=$2
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$OUT"

empty_sarif() { printf '{"version":"2.1.0","runs":[]}' > "$1"; }
valid_or_empty() {
  local f=$1
  if [ -s "$f" ] && python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" 2>/dev/null; then
    return 0
  fi
  empty_sarif "$f"
}
log() { printf '\n==> %s\n' "$*" >&2; }

install() { # url... | tar -xz -C /usr/local/bin <binary>
  curl -fsSL "$@" >/dev/null 2>&1
}

### semgrep (multi-language SAST + custom sealos rules)
log semgrep
pipx install semgrep >/dev/null 2>&1 || pipx upgrade semgrep >/dev/null 2>&1 || true
if command -v semgrep >/dev/null 2>&1; then
  semgrep scan \
    --config p/owasp-top-ten \
    --config p/security-audit \
    --config p/secrets \
    --config p/kubernetes \
    --config p/dockerfile \
    --config "$ROOT/semgrep-rules" \
    --sarif --metrics=off \
    --timeout 60 --timeout-threshold 3 \
    "$SRC" > "$OUT/semgrep.sarif" 2>/dev/null || true
fi
valid_or_empty "$OUT/semgrep.sarif"

### gitleaks (secrets)
log gitleaks
GL_VER=8.24.3
if ! command -v gitleaks >/dev/null 2>&1; then
  curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GL_VER}/gitleaks_${GL_VER}_linux_x64.tar.gz" \
    | tar -xz -C /usr/local/bin gitleaks >/dev/null 2>&1 || true
fi
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks detect \
    --source "$SRC" --no-git --redact \
    --config "$ROOT/.gitleaks.toml" \
    --report-format sarif --report-path "$OUT/gitleaks.sarif" \
    >/dev/null 2>&1 || true
fi
valid_or_empty "$OUT/gitleaks.sarif"

### gosec (Go SAST, per module)
log gosec
if find "$SRC" -name go.mod -not -path '*/vendor/*' | grep -q .; then
  go install github.com/securego/gosec/v2/cmd/gosec@v2.22.3 >/dev/null 2>&1 || true
  GOSEC_BIN="$(go env GOPATH)/bin/gosec"
  if [ -x "$GOSEC_BIN" ]; then
    i=0
    while IFS= read -r mod; do
      d="$(dirname "$mod")"
      case "$d" in */staging*|*/vendor*) continue ;; esac
      i=$((i+1))
      "$GOSEC_BIN" -no-fail -exclude-generated \
        -severity medium -confidence medium \
        -fmt sarif -out "$OUT/gosec-$i.sarif" "$d/..." >/dev/null 2>&1 || true
      valid_or_empty "$OUT/gosec-$i.sarif"
    done < <(find "$SRC" -name go.mod -not -path '*/vendor/*')
  fi
fi
[ -s "$OUT/gosec-1.sarif" ] || empty_sarif "$OUT/gosec.sarif"

### osv-scanner (dependency advisories: go.sum / lockfiles)
log osv-scanner
OSV_VER=2.0.2
if ! command -v osv-scanner >/dev/null 2>&1; then
  curl -fsSL "https://github.com/google/osv-scanner/releases/download/v${OSV_VER}/osv-scanner_linux_amd64" \
    -o /usr/local/bin/osv-scanner >/dev/null 2>&1 && chmod +x /usr/local/bin/osv-scanner || true
fi
if command -v osv-scanner >/dev/null 2>&1; then
  osv-scanner -r --format sarif --output "$OUT/osv.sarif" "$SRC" >/dev/null 2>&1 || true
fi
valid_or_empty "$OUT/osv.sarif"

### kube-linter (K8s charts / manifests)
log kube-linter
KL_VER=v0.7.5
if ! command -v kube-linter >/dev/null 2>&1; then
  curl -fsSL "https://github.com/stackrox/kube-linter/releases/download/${KL_VER}/kube-linter-linux.tar.gz" \
    | tar -xz -C /usr/local/bin kube-linter >/dev/null 2>&1 || true
fi
if command -v kube-linter >/dev/null 2>&1; then
  if find "$SRC" \( -name Chart.yaml -o -name 'k8s.yaml' \) -not -path '*/node_modules/*' | grep -q .; then
    kube-linter lint "$SRC" --format sarif > "$OUT/kube-linter.sarif" 2>/dev/null || true
  fi
fi
valid_or_empty "$OUT/kube-linter.sarif"

### hadolint (Dockerfile)
log hadolint
HD_VER=2.12.0
if ! command -v hadolint >/dev/null 2>&1; then
  curl -fsSL "https://github.com/hadolint/hadolint/releases/download/v${HD_VER}/hadolint-Linux-x86_64" \
    -o /usr/local/bin/hadolint >/dev/null 2>&1 && chmod +x /usr/local/bin/hadolint || true
fi
if command -v hadolint >/dev/null 2>&1; then
  mapfile -t DFS < <(find "$SRC" -name 'Dockerfile*' -not -path '*/node_modules/*' -not -path '*/vendor/*')
  if ((${#DFS[@]})); then
    hadolint -f sarif "${DFS[@]}" > "$OUT/hadolint.sarif" 2>/dev/null || true
  fi
fi
valid_or_empty "$OUT/hadolint.sarif"

### zizmor (GitHub Actions workflows of the target)
log zizmor
if [ -d "$SRC/.github/workflows" ]; then
  pipx install zizmor >/dev/null 2>&1 || true
  if command -v zizmor >/dev/null 2>&1; then
    zizmor --format sarif --no-online-audits "$SRC" > "$OUT/zizmor.sarif" 2>/dev/null || true
  fi
fi
valid_or_empty "$OUT/zizmor.sarif"

### bandit (Python)
log bandit
if find "$SRC" -name '*.py' -not -path '*/vendor/*' -not -path '*/node_modules/*' | grep -q .; then
  pipx run bandit -r -q -f sarif -o "$OUT/bandit.sarif" \
    --exclude '*/test*,*/vendor/*,*/node_modules/*,*/.venv/*' "$SRC" >/dev/null 2>&1 || true
fi
valid_or_empty "$OUT/bandit.sarif"

log done
