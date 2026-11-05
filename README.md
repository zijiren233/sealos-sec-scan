# sealos-sec-scan

Scheduled static security scanning for the sealos platform repositories (main repo + sealos-apps ecosystem). Runs every week and on demand; findings land in the GitHub **Security** tab and in a pinned tracking issue.

## Tools

| Tool | Scope | Output |
|------|-------|--------|
| CodeQL (`security-extended`, no-build languages) | SAST — JS/TS, Python (Go via gosec) | category `<target>-codeql` |
| Semgrep (owasp-top-ten, security-audit, secrets, kubernetes, dockerfile + custom `semgrep-rules/`) | SAST + config | merged SARIF |
| Gitleaks | secret leakage (file mode, HEAD) | merged SARIF |
| Gosec (per Go module) | Go SAST | merged SARIF |
| Trivy (vuln + misconfig + secret, binary) | dependencies, IaC, Dockerfiles | merged SARIF |
| OSV-Scanner | dependency advisories (go.sum / lockfiles) | merged SARIF |
| kube-linter | Helm charts / K8s manifests | merged SARIF |
| hadolint | Dockerfiles | merged SARIF |
| zizmor | target's GitHub Actions workflows | merged SARIF |
| bandit | Python | merged SARIF |

Custom rules in `semgrep-rules/` encode platform-specific failure modes: caller-supplied kubeconfig flowing into `loadFromString` / client-go `clientcmd` (credential-plugin execution), shell `exec` with interpolated template literals, wildcard `ClusterRole` grants on secrets/pods/service accounts, and azure/gcp `auth-provider` kubeconfig payloads.

## Usage

- **Schedule**: Sundays 02:00 UTC.
- **Manual run**: Actions → *Static Security Scan* → *Run workflow*. The `only` input filters targets by regex (e.g. `devbox|sealaf`).
- **Add a target**: append an entry to `targets.yaml`.
- **Results**: Security → Code scanning (category `<target>` for the tool suite, `<target>-codeql` for CodeQL); full per-tool SARIF in the run artifacts; counts pinned in the *Static Scan Results* issue.

## Local run

```bash
scripts/local-run.sh /path/to/sealos-checkout out
```

Requires the tools on PATH (brew/pipx/go install); each step skips silently when a tool is missing.

## Notes

- Tool binaries are version-pinned in `scripts/run-tools.sh`; bump them there.
- A single tool failure never fails a scan job — every SARIF slot is backfilled with a valid empty document.
- `node_modules`, `vendor`, lockfiles and the main repo's vendored `lifecycle/staging` tree are excluded from SAST to keep signal high; Trivy still scans lockfiles for known CVEs.

## Private targets

`sealos-apps/*` repositories are private. To scan them, create a fine-grained
personal access token (Contents: Read-only on the `sealos-apps` organization)
and add it as the `TARGET_TOKEN` secret in this repository. Without the secret,
private targets are skipped with a warning and public targets still scan.
