#!/usr/bin/env bash
# Bootstrap local pre-commit security scanning (Gitleaks + Semgrep).
# Works on macOS and Linux. Idempotent.
#
# Usage:  bash scripts/install-security-hooks.sh
# Re-run any time: it preserves existing config files and re-installs hooks.

set -euo pipefail

# ---------- output helpers ----------
if [ -t 1 ]; then
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_RESET=$'\033[0m'
else
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_RESET=""
fi
info() { printf "%s[i]%s %s\n" "$C_BLUE"   "$C_RESET" "$*"; }
ok()   { printf "%s[+]%s %s\n" "$C_GREEN"  "$C_RESET" "$*"; }
warn() { printf "%s[!]%s %s\n" "$C_YELLOW" "$C_RESET" "$*"; }
fail() { printf "%s[x]%s %s\n" "$C_RED"    "$C_RESET" "$*" >&2; exit 1; }

# ---------- sanity: git repo ----------
git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "Not inside a git repository. cd to your repo root and rerun."
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"
info "Repo root: $REPO_ROOT"

# ---------- OS / arch detection ----------
case "$(uname -s)" in
  Darwin) OS_KIND=macos; GL_OS=darwin ;;
  Linux)  OS_KIND=linux; GL_OS=linux  ;;
  *)      fail "Unsupported OS: $(uname -s) (installer supports macOS and Linux)" ;;
esac
case "$(uname -m)" in
  x86_64|amd64)  ARCH_KIND=x64 ;;
  arm64|aarch64) ARCH_KIND=arm64 ;;
  *)             ARCH_KIND="$(uname -m)"; warn "Unrecognized arch $ARCH_KIND; gitleaks binary fallback may fail" ;;
esac
info "OS: $OS_KIND  arch: $ARCH_KIND"

# ---------- detect installers (priority: brew > pipx > pip3) ----------
HAS_BREW=0; HAS_PIPX=0; HAS_PIP3=0
command -v brew >/dev/null 2>&1 && HAS_BREW=1
command -v pipx >/dev/null 2>&1 && HAS_PIPX=1
command -v pip3 >/dev/null 2>&1 && HAS_PIP3=1
if   [ "$HAS_BREW" = 1 ]; then ok "Using brew for installs"
elif [ "$HAS_PIPX" = 1 ]; then ok "Using pipx for Python tools"
elif [ "$HAS_PIP3" = 1 ]; then warn "Falling back to 'pip3 install --user' — consider installing pipx"
else fail "No supported installer found. Install one of: brew, pipx, pip3."
fi

ensure_local_bin_on_path() {
  if ! echo ":$PATH:" | grep -q ":$HOME/.local/bin:"; then
    warn '$HOME/.local/bin is not on PATH. Add this to your shell rc:'
    warn '  export PATH="$HOME/.local/bin:$PATH"'
    export PATH="$HOME/.local/bin:$PATH"
  fi
}

# ---------- pre-commit ----------
if command -v pre-commit >/dev/null 2>&1; then
  ok "pre-commit already installed: $(pre-commit --version)"
else
  info "Installing pre-commit..."
  if   [ "$HAS_BREW" = 1 ]; then brew install pre-commit
  elif [ "$HAS_PIPX" = 1 ]; then pipx install pre-commit && ensure_local_bin_on_path
  else pip3 install --user pre-commit && ensure_local_bin_on_path
  fi
  ok "pre-commit installed"
fi

# ---------- semgrep ----------
if command -v semgrep >/dev/null 2>&1; then
  ok "semgrep already installed: $(semgrep --version 2>/dev/null | head -n1)"
else
  info "Installing semgrep..."
  if   [ "$HAS_BREW" = 1 ]; then brew install semgrep
  elif [ "$HAS_PIPX" = 1 ]; then pipx install semgrep && ensure_local_bin_on_path
  else pip3 install --user semgrep && ensure_local_bin_on_path
  fi
  ok "semgrep installed"
fi

# ---------- gitleaks ----------
if command -v gitleaks >/dev/null 2>&1; then
  ok "gitleaks already installed: $(gitleaks version)"
else
  info "Installing gitleaks..."
  if [ "$HAS_BREW" = 1 ]; then
    brew install gitleaks
  else
    info "Fetching latest gitleaks release metadata..."
    GL_VERSION="$(curl -fsSL https://api.github.com/repos/gitleaks/gitleaks/releases/latest \
      | grep '"tag_name"' \
      | head -n1 \
      | sed -E 's/.*"v?([^"]+)".*/\1/')"
    [ -n "${GL_VERSION:-}" ] || fail "Could not determine latest gitleaks version (network?)"
    GL_TARBALL="gitleaks_${GL_VERSION}_${GL_OS}_${ARCH_KIND}.tar.gz"
    GL_URL="https://github.com/gitleaks/gitleaks/releases/download/v${GL_VERSION}/${GL_TARBALL}"
    info "Downloading $GL_URL"
    mkdir -p "$HOME/.local/bin"
    curl -fsSL "$GL_URL" | tar -xz -C "$HOME/.local/bin" gitleaks
    chmod +x "$HOME/.local/bin/gitleaks"
    ensure_local_bin_on_path
  fi
  ok "gitleaks installed: $(gitleaks version)"
fi

# ---------- write config files (only if missing) ----------
write_if_missing() {
  local path="$1"
  if [ -e "$path" ]; then
    warn "Keeping existing $path"
    return
  fi
  mkdir -p "$(dirname "$path")"
  cat > "$path"
  ok "Wrote $path"
}

write_if_missing ".pre-commit-config.yaml" <<'PRECOMMIT_EOF'
# Local security gate: Gitleaks (secrets, blocking) + Semgrep (SAST, ERROR-only blocking).
# Hook stages:
#   pre-commit  -> staged files only, blocking
#   pre-push    -> upstream..HEAD diff, blocking
#   post-merge  -> advisory after git pull / git merge (never blocks)
# Bootstrap with: bash scripts/install-security-hooks.sh
#
# Every local hook is wrapped in `bash -c 'export PATH=...; ...'` so tools resolve
# correctly regardless of the caller's PATH (IDE, Husky, CI all have different PATHs).

fail_fast: false
default_stages: [pre-commit]
minimum_pre_commit_version: "3.5.0"

repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks:
      - id: check-merge-conflict
      - id: check-added-large-files
        args: [--maxkb=1024]
      - id: detect-private-key
      - id: check-yaml
        args: [--allow-multiple-documents]
      - id: check-json
        exclude: ^(tsconfig.*\.json|.*\.code-workspace)$

  - repo: local
    hooks:
      # ---------- pre-commit stage: staged files, blocking ----------
      - id: gitleaks-staged
        name: gitleaks (staged diff)
        entry: bash -c 'export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"; exec gitleaks protect --staged --redact --verbose'
        language: system
        pass_filenames: false
        always_run: true
        stages: [pre-commit]

      - id: semgrep-staged
        name: semgrep (staged files, ERROR blocks)
        entry: bash -c 'export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"; exec semgrep scan --error --severity=ERROR --metrics=off --quiet --config=p/secrets --config=p/security-audit --config=p/owasp-top-ten --config=p/javascript --config=p/typescript --config=p/nodejs --config=p/nodejsscan --config=p/react --config=p/nextjs --config=p/php --config=p/docker "$@"' --
        language: system
        types_or: [javascript, jsx, ts, tsx, php, yaml, json, dockerfile]
        stages: [pre-commit]

      # ---------- pre-push stage: upstream..HEAD diff, blocking ----------
      - id: gitleaks-prepush
        name: gitleaks (upstream..HEAD)
        entry: bash -c 'export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"; set -e; range="@{upstream}..HEAD"; if ! git rev-parse "@{upstream}" >/dev/null 2>&1; then echo "no upstream tracked; scanning full history"; range=""; fi; gitleaks detect --source . ${range:+--log-opts="$range"} --redact --verbose'
        language: system
        pass_filenames: false
        always_run: true
        stages: [pre-push]

      - id: semgrep-prepush
        name: semgrep (upstream..HEAD, ERROR blocks)
        entry: bash -c 'export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"; set -e; if ! git rev-parse "@{upstream}" >/dev/null 2>&1; then range="HEAD~1..HEAD"; else range="@{upstream}..HEAD"; fi; files=$(git diff --name-only --diff-filter=ACMR "$range" 2>/dev/null || true); if [ -z "$files" ]; then echo "no changed files to scan"; exit 0; fi; printf "%s\n" "$files" | tr "\n" "\0" | xargs -0 semgrep scan --error --severity=ERROR --metrics=off --quiet --config=p/secrets --config=p/security-audit --config=p/owasp-top-ten --config=p/javascript --config=p/typescript --config=p/nodejs --config=p/nodejsscan --config=p/react --config=p/nextjs --config=p/php --config=p/docker'
        language: system
        pass_filenames: false
        always_run: true
        stages: [pre-push]

      # ---------- post-merge stage: advisory (never blocks) ----------
      - id: gitleaks-postmerge
        name: gitleaks (post-merge advisory)
        entry: bash -c 'export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"; echo "[advisory] scanning merged commits for secrets..."; gitleaks detect --source . --log-opts="ORIG_HEAD..HEAD" --redact --verbose || true'
        language: system
        pass_filenames: false
        always_run: true
        stages: [post-merge]
        verbose: true

      - id: semgrep-postmerge
        name: semgrep (post-merge advisory)
        entry: bash -c 'export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"; files=$(git diff-tree -r --name-only --no-commit-id ORIG_HEAD HEAD 2>/dev/null || true); if [ -z "$files" ]; then exit 0; fi; echo "[advisory] scanning merged files with semgrep..."; printf "%s\n" "$files" | tr "\n" "\0" | xargs -0 semgrep scan --severity=ERROR --metrics=off --quiet --config=p/security-audit --config=p/owasp-top-ten --config=p/javascript --config=p/typescript --config=p/nodejs --config=p/php --config=p/docker || true'
        language: system
        pass_filenames: false
        always_run: true
        stages: [post-merge]
        verbose: true
PRECOMMIT_EOF

write_if_missing ".semgrepignore" <<'SEMGREPIGNORE_EOF'
# Semgrep ignore patterns. Single source of truth for path exclusions.

.git/
node_modules/
vendor/

dist/
build/
coverage/
.nyc_output/
.next/
.turbo/
out/

storage/
bootstrap/cache/
public/build/

*.min.js
*.bundle.js
*.map
package-lock.json
yarn.lock
composer.lock
pnpm-lock.yaml

attached_assets/
docs/

src/migrations/
database/migrations/
SEMGREPIGNORE_EOF

write_if_missing ".gitleaks.toml" <<'GITLEAKS_EOF'
title = "Local gitleaks config"

[extend]
useDefault = true

[allowlist]
description = "Allowed paths and patterns for legitimate placeholder secrets"
paths = [
  '''\.env\.example$''',
  '''\.env\.test$''',
  '''\.env\.sample$''',
  '''(^|/)tests?/.*\.(json|ya?ml)$''',
  '''(^|/)docs/''',
  '''(^|/)attached_assets/''',
]
GITLEAKS_EOF

# ---------- add generated files to .gitignore (per-developer setup) ----------
ensure_gitignore_entries() {
  local ignore=".gitignore"
  local marker="# Local security-scanning setup"
  if [ -f "$ignore" ] && grep -qF "$marker" "$ignore"; then
    warn "Keeping existing .gitignore entries for security tooling"
    return
  fi
  # Make sure file ends with a newline before appending
  if [ -f "$ignore" ] && [ -s "$ignore" ] && [ "$(tail -c1 "$ignore")" != "" ]; then
    printf "\n" >> "$ignore"
  fi
  cat >> "$ignore" <<'GITIGNORE_EOF'

# Local security-scanning setup (per-developer; bootstrap via scripts/install-security-hooks.sh)
.pre-commit-config.yaml
.semgrepignore
.gitleaks.toml
scripts/install-security-hooks.sh
GITIGNORE_EOF
  ok "Added security-tooling entries to .gitignore"
}
ensure_gitignore_entries

# ---------- install git hooks ----------
info "Installing git hooks: pre-commit, pre-push, post-merge..."
pre-commit install --hook-type pre-commit >/dev/null
pre-commit install --hook-type pre-push   >/dev/null
pre-commit install --hook-type post-merge >/dev/null
ok "Git hooks installed"

# ---------- pre-warm semgrep cache ----------
info "Pre-warming semgrep rule cache (one-time, ~30-60s)..."
semgrep scan \
  --config=p/security-audit \
  --config=p/javascript \
  --severity=ERROR \
  --metrics=off \
  --quiet . >/dev/null 2>&1 || true
ok "Semgrep cache warmed"

# ---------- summary ----------
cat <<EOF

${C_GREEN}=== Setup complete ===${C_RESET}

Installed hooks:
  pre-commit   -> blocks on staged secrets + ERROR-severity SAST findings
  pre-push     -> blocks on secrets + ERROR-severity SAST findings (upstream..HEAD)
  post-merge   -> advisory scan after git pull / git merge (never blocks)

Manual scan commands:
  pre-commit run                                     # staged files
  pre-commit run --all-files                         # entire repo
  pre-commit run --hook-stage pre-push --all-files   # pre-push hooks
  gitleaks detect --source . --redact --verbose      # full repo secret scan
  semgrep scan --metrics=off --config=auto           # full repo SAST

Bypass (emergencies only):  git commit --no-verify  /  git push --no-verify
Update hook revisions:      pre-commit autoupdate
Uninstall:                  pre-commit uninstall --hook-type pre-commit --hook-type pre-push --hook-type post-merge
EOF
