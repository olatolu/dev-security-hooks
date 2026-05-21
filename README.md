# dev-security-hooks

Bootstrap local pre-commit security scanning (Gitleaks + Semgrep) in any git repo. macOS and Linux.

## Quick start

In any git repo:

```bash
mkdir -p scripts
curl -fsSL https://raw.githubusercontent.com/olatolu/dev-security-hooks/v1.0.0/install-security-hooks.sh \
  -o scripts/install-security-hooks.sh
chmod +x scripts/install-security-hooks.sh
bash scripts/install-security-hooks.sh
```

That's it. The installer detects your OS and package manager (brew → pipx → pip3), installs `pre-commit`, `gitleaks`, and `semgrep` as needed, writes the configs, registers commit/push/post-merge hooks, and adds the configs to `.gitignore` so each developer bootstraps their own.

## What you get

| Stage | Tool | Behavior |
|---|---|---|
| `pre-commit` | gitleaks + semgrep | Scans staged files. **Blocks** on any secret or ERROR-severity SAST finding. |
| `pre-push` | gitleaks + semgrep | Scans the `upstream..HEAD` diff. **Blocks** before code leaves the machine. |
| `post-merge` | gitleaks + semgrep | Scans newly merged files after `git pull`. **Advisory only** — flags issues but never undoes the merge. |

Semgrep registry rules cover JavaScript, TypeScript, Node.js, NestJS, Next.js, Fastify, React, PHP, Docker, plus generic security-audit and OWASP Top 10. Gitleaks uses its default ruleset plus an allowlist for `.env.example` and similar placeholders.

## With Claude Code

Open a Claude Code session in any repo and tell it:

> Follow https://raw.githubusercontent.com/olatolu/dev-security-hooks/v1.0.0/setup-security-hooks.md to set up local security scanning here.

Claude reads the doc, installs the tools, writes the configs, registers the hooks, and prints a summary. Useful when you want one of your existing repos onboarded without running shell commands yourself.

## Manual commands once installed

```bash
pre-commit run --all-files                    # scan entire repo
pre-commit run --hook-stage pre-push --all-files
gitleaks detect --source . --redact --verbose
semgrep scan --metrics=off --config=auto
pre-commit autoupdate                         # update hook revisions
git commit --no-verify                        # bypass (emergencies only)
```

## Files

- [`install-security-hooks.sh`](./install-security-hooks.sh) — the installer (self-contained; configs embedded as heredocs)
- [`setup-security-hooks.md`](./setup-security-hooks.md) — Claude Code instruction doc (full file contents + step-by-step)

## License

MIT — do whatever you want with it.
