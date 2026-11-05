#!/usr/bin/env bash
# Merge all per-tool SARIF files into out/merged.sarif for a single
# code-scanning upload (one category per target). Pure-python merge:
# deterministic, no npx, no tool-version splitting.
set -uo pipefail
OUT=$1

rm -rf "$OUT/merged.sarif"

python3 - "$OUT" <<'PY'
import glob, json, os, sys

out = sys.argv[1]
files = [f for f in sorted(glob.glob(os.path.join(out, "**", "*.sarif"), recursive=True))
         if os.path.isfile(f)]

by_driver = {}
for f in files:
    try:
        doc = json.load(open(f))
    except Exception:
        continue
    for run in doc.get("runs", []):
        name = run.get("tool", {}).get("driver", {}).get("name") or os.path.basename(f)
        n = len(run.get("results") or [])
        if name not in by_driver or n > len(by_driver[name].get("results") or []):
            by_driver[name] = run

runs = list(by_driver.values())
doc = {
    "version": "2.1.0",
    "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
    "runs": runs,
}
path = os.path.join(out, "merged.sarif")
json.dump(doc, open(path, "w"))
print(f"merged {len(files)} files, {len(runs)} tool runs, "
      f"{sum(len(r.get('results') or []) for r in runs)} findings")
PY

if ! [ -s "$OUT/merged.sarif" ]; then
  printf '{"version":"2.1.0","runs":[]}' > "$OUT/merged.sarif"
fi
