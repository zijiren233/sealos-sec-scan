#!/usr/bin/env bash
# Aggregate per-target finding counts and pin them to a single tracking issue.
set -uo pipefail
RUN_URL=$1
RESULTS_DIR=${2:-results}
REPO=${GITHUB_REPOSITORY:-}

rows=""
total=0
scanned=0

for d in "$RESULTS_DIR"/sarif-*/; do
  [ -d "$d" ] || continue
  t="$(basename "$d" | sed 's/^sarif-//')"
  s="$d/out/merged.sarif"
  [ -s "$s" ] || continue
  n="$(jq -r '[.runs[]?.results[]?] | length' "$s" 2>/dev/null || echo 0)"
  scanned=$((scanned+1))
  total=$((total+n))
  rows="${rows}| ${t} | ${n} |
"
done

if [ -z "$rows" ]; then
  echo "no artifacts found; nothing to summarize"
  exit 0
fi

BODY="## Static scan results

Last run: ${RUN_URL} ($(date -u '+%Y-%m-%d %H:%M UTC'))

Targets scanned: ${scanned} · Total findings (all tools except CodeQL): ${total}

Per-target findings:

| Target | Findings |
|--------|---------:|
${rows}
Detailed results: repo **Security → Code scanning** (categories \\\`<target>\\\` and \\\`<target>-codeql\\\`) and run artifacts (full SARIF per tool)."

IID=$(gh issue list --repo "$REPO" --state open --search 'in:title "Static Scan Results"' --json number --jq '.[0].number' 2>/dev/null || true)
if [ -z "${IID:-}" ]; then
  gh issue create --repo "$REPO" --title "Static Scan Results" --body "$BODY"
else
  gh issue edit "$IID" --repo "$REPO" --body "$BODY"
fi
echo "summary issue updated"
