# dev-security-hooks

Self-serve security setup for any git repo. macOS and Linux.

Two independent setups inside this repo — install one, both, or neither:

| What | Why | Pinned URL |
|---|---|---|
| [Local pre-commit scanning](#1-local-pre-commit-scanning-gitleaks--semgrep) | Block secrets + ERROR-severity SAST findings before they leave your machine. | `v1.2.0` |
| [GPG commit signing](#2-gpg-commit-signing) | Get the GitHub "Verified" badge on every commit; satisfies signed-commit branch protection. | `v1.2.0` |

---

## 1. Local pre-commit scanning (Gitleaks + Semgrep)

### Quick start (any repo)

```bash
mkdir -p scripts
curl -fsSL https://raw.githubusercontent.com/olatolu/dev-security-hooks/v1.2.0/install-security-hooks.sh \
  -o scripts/install-security-hooks.sh
chmod +x scripts/install-security-hooks.sh
bash scripts/install-security-hooks.sh
```

The installer detects your OS and package manager (brew → pipx → pip3), installs `pre-commit`, `gitleaks`, and `semgrep` as needed, writes the configs, registers commit/push/post-merge hooks, and adds the configs to `.gitignore` (per-developer setup).

### What you get

| Stage | Tool | Behavior |
|---|---|---|
| `pre-commit` | gitleaks + semgrep | Scans staged files. **Blocks** on any secret or ERROR-severity SAST finding. |
| `pre-push` | gitleaks + semgrep | Scans the `upstream..HEAD` diff. **Blocks** before code leaves the machine. |
| `post-merge` | gitleaks + semgrep | Scans newly merged files after `git pull`. **Advisory only** — flags issues but never undoes the merge. |

Semgrep registry rules cover JavaScript, TypeScript, Node.js, NestJS, Next.js, Fastify, React, PHP, Docker, plus generic security-audit and OWASP Top 10. Gitleaks uses its default ruleset plus an allowlist for `.env.example` and similar placeholders.

**Custom malware-loader detection** (added in v1.2.0): catches DEV#POPPER-family payloads that inject obfuscated JavaScript into config files (`jest.config.js`, `postcss.config.mjs`, etc.). Layered defense — Gitleaks signature rules, a Semgrep YAML rule pack, and a long-line check on config files (anything >500 chars in a `*.config.{js,mjs,cjs,ts}` blocks). Standard registry rules don't catch this; the custom layer does.

### With Claude Code

> Follow https://raw.githubusercontent.com/olatolu/dev-security-hooks/v1.2.0/setup-security-hooks.md to set up local security scanning here.

### Manual commands once installed

```bash
pre-commit run --all-files                            # scan entire repo
pre-commit run --hook-stage pre-push --all-files
gitleaks detect --source . --redact --verbose
semgrep scan --metrics=off --config=auto
pre-commit autoupdate                                 # update hook revisions
git commit --no-verify                                # bypass (emergencies only)
```

---

## 2. GPG commit signing

For the GitHub **Verified** badge and to satisfy signed-commit branch protection.

### With Claude Code (recommended)

Open Claude Code on your machine and say:

> Follow https://raw.githubusercontent.com/olatolu/dev-security-hooks/v1.2.0/setup-gpg-signing.md to set up GPG commit signing.

Claude installs GnuPG + pinentry, configures gpg-agent for IDE-friendly passphrase prompts, walks you through key generation, writes the git config (asking whether you want it **global** or **scoped to a directory** — pick scoped if you commit as different identities for personal projects vs work), and helps you upload the public key to GitHub.

### Manual / no-Claude path

Read [`setup-gpg-signing.md`](./setup-gpg-signing.md) and follow the "What Claude should do" checklist yourself. It's a plain step-by-step.

### What you get

- A 4096-bit RSA GPG key, 1-year expiry (rotate yearly).
- `commit.gpgsign = true` either globally or scoped to a directory of your choice via `includeIf` (the scoped option leaves your other repos untouched).
- pinentry configured so passphrase prompts work from terminal **and** IDEs (VS Code, JetBrains).
- Public key uploaded to GitHub.

---

## Files

- [`install-security-hooks.sh`](./install-security-hooks.sh) — self-contained installer for the pre-commit setup (configs embedded as heredocs).
- [`setup-security-hooks.md`](./setup-security-hooks.md) — Claude Code instruction doc for the pre-commit setup.
- [`setup-gpg-signing.md`](./setup-gpg-signing.md) — Claude Code instruction doc for GPG commit signing.

## Releases

Pinned URLs use a git tag for tamper-resistance. Always reference the latest tag in the table at the top of this README. Current: **v1.2.0**.

**Upgrading from an older version:** because the installer is idempotent and preserves existing configs, an in-place re-run won't pick up new rules. To upgrade, delete the locally-installed configs and re-run:

```bash
rm -f .pre-commit-config.yaml .semgrepignore .gitleaks.toml
rm -rf .semgrep-rules
bash scripts/install-security-hooks.sh
```

## License

MIT — do whatever you want with it.
