# Setup: GPG Commit Signing

> **For Claude:** This document is a self-contained instruction set. When pointed at this file, follow the **"What Claude should do"** section below. All commands are embedded — do not fetch from the network.

---

## Purpose & policy

Cutstruct (Lede) requires all commits to be GPG-signed so GitHub shows the **Verified** badge. This blocks force-pushes and unverified commits across the org's repos.

This doc sets up GPG signing in one of two modes:

- **Global** — applies to every git repo on the machine. Simple. Use it if this is a single-purpose laptop or you only ever commit as one identity.
- **Scoped (recommended for multi-client laptops)** — signing only activates inside a chosen directory (e.g. `~/Code/<your-org>/`). Other repos on the same machine are untouched and keep their existing identities. Implemented via `[includeIf "gitdir:<path>"]` in `~/.gitconfig`.

Supports **macOS and Linux**.

---

## What Claude should do

Execute these steps in order. **Pause and ask the user** when a step is marked `[user input]` or when the answer drives later configuration.

### 1. Detect environment

- OS: `uname -s` → `Darwin` (macOS) or `Linux`
- Shell: `echo $SHELL` → `zsh` / `bash` / `fish` — controls which rc file to append `GPG_TTY` to
- Package manager: prefer `brew` on macOS or Linuxbrew; fall back to `apt`, `dnf`, `pacman` on Linux

### 2. Install GPG + pinentry

**macOS:**
```bash
brew install gnupg pinentry-mac
```

**Linux (Debian/Ubuntu):**
```bash
sudo apt update && sudo apt install -y gnupg pinentry-tty
```

**Linux (Fedora/RHEL):**
```bash
sudo dnf install -y gnupg2 pinentry-tty
```

**Linux (Arch):**
```bash
sudo pacman -S --needed gnupg pinentry
```

Verify: `gpg --version` shows 2.x.

### 3. Configure gpg-agent to use the GUI pinentry

This is the #1 source of "GPG commits don't work in my IDE" tickets. Without a GUI pinentry, IDE commits hang silently because they can't show a passphrase prompt.

**macOS:**
```bash
mkdir -p ~/.gnupg && chmod 700 ~/.gnupg
grep -q '^pinentry-program' ~/.gnupg/gpg-agent.conf 2>/dev/null \
  || printf 'pinentry-program /usr/local/bin/pinentry-mac\n' >> ~/.gnupg/gpg-agent.conf
# Apple Silicon path is /opt/homebrew/bin/pinentry-mac — adjust if `which pinentry-mac` differs
chmod 600 ~/.gnupg/gpg-agent.conf
gpgconf --kill gpg-agent
```

**Linux:** pinentry-tty handles the prompt in the same terminal that invoked GPG, so no agent config tweak is strictly needed. If using a desktop environment, install `pinentry-gnome3` (GNOME) or `pinentry-qt` (KDE) instead and point to it the same way.

### 4. Add `GPG_TTY` to shell rc (safety net for terminal-only flows)

```bash
RC="$HOME/.zshrc"
[ -n "$BASH_VERSION" ] || [ "$(basename "$SHELL")" = "bash" ] && RC="$HOME/.bashrc"
grep -q 'GPG_TTY' "$RC" \
  || printf '\n# GPG signing\nexport GPG_TTY=$(tty)\n' >> "$RC"
```

### 5. `[user input]` Pick global vs scoped

Ask the user:

> Do you want GPG signing applied globally (every repo on this machine signs commits with your work identity), or scoped to a specific directory (recommended if you work on personal projects, OSS, or other clients on the same laptop)?

If scoped, ask for the directory prefix (typical answer: `~/Code/<your-org>/`).

### 6. `[user input]` Generate the GPG key

GPG cannot script the passphrase entry. **Tell the user to run this in their own terminal** (not via Claude's bash, which has no controlling TTY and will fail with `cannot open '/dev/tty': Device not configured`):

```bash
gpg --quick-generate-key '<Your Name> <your-email@example.com>' rsa4096 default 1y
```

- `<Your Name>` and `<your-email@example.com>` must match the user's GitHub-verified commit email — otherwise GitHub will not display the Verified badge.
- Expiry `1y` is recommended (rotate yearly). Use `0` for no expiry only if you have a strong reason.
- A pinentry dialog will appear; the user chooses a strong passphrase and saves it in a password manager.

After the key is generated, capture the key ID:

```bash
KEY_ID=$(gpg --list-secret-keys --keyid-format=long --with-colons \
  | awk -F: '/^sec/ {print $5; exit}')
echo "$KEY_ID"
```

### 7. Write the git config

**If global:**

```bash
git config --global user.name "<Your Name>"
git config --global user.email "<your-email@example.com>"
git config --global user.signingkey "$KEY_ID"
git config --global commit.gpgsign true
git config --global tag.gpgsign true
git config --global gpg.program "$(which gpg)"
```

**If scoped to `~/Code/<your-org>/`:**

Write a separate config file the user can audit:

```bash
ORG_DIR="$HOME/Code/<your-org>"        # adjust to match the user's answer
SCOPED_CFG="$HOME/.gitconfig-<your-org>"
cat > "$SCOPED_CFG" <<EOF
# Org-only git config. Activated by [includeIf "gitdir:$ORG_DIR/"] in ~/.gitconfig.
# Does not affect other repos on this machine.
[user]
    name = <Your Name>
    email = <your-email@example.com>
    signingkey = $KEY_ID
[commit]
    gpgsign = true
[tag]
    gpgsign = true
[gpg]
    program = $(which gpg)
EOF

git config --global --add "includeIf.gitdir:$ORG_DIR/.path" "$SCOPED_CFG"
```

The trailing slash on the `gitdir:` match is required for prefix matching.

### 8. Upload the public key to GitHub

**Simplest (works with any GitHub login, no extra OAuth scopes):**

macOS:
```bash
gpg --armor --export "$KEY_ID" | pbcopy
open https://github.com/settings/gpg/new
```

Linux:
```bash
gpg --armor --export "$KEY_ID" | xclip -selection clipboard   # or: xsel -b -i
xdg-open https://github.com/settings/gpg/new                  # or open in browser manually
```

Paste, name the key (e.g. `<org> laptop ($(hostname -s))`), click Add GPG key.

**CLI alternative** (if `gh` is installed and the active account is correct):

```bash
gh gpg-key add <(gpg --armor --export "$KEY_ID") --title "<org> laptop ($(hostname -s))"
```

If `gh` complains about OAuth scopes, run `gh auth refresh -s write:gpg_key,read:gpg_key` and complete the browser flow, or fall back to the web UI.

### 9. Verify

```bash
# 1. gpg can sign locally
echo "test" | gpg --clearsign --local-user "$KEY_ID" >/dev/null && echo "gpg sign OK"

# 2. inside the target org dir: signing is active
cd $ORG_DIR/<any-existing-repo>            # for global mode: any repo
git config --get user.signingkey            # should print $KEY_ID
git config --get commit.gpgsign             # should print "true"

# 3. real signed commit
git commit --allow-empty -m "test: GPG signing"
git log --show-signature -1                 # look for "gpg: Good signature"

# 4. (scoped mode only) outside the org dir: signing must NOT be active
TMP=$(mktemp -d) && cd "$TMP" && git init -q test && cd test
git config --get commit.gpgsign             # should print nothing
cd / && rm -rf "$TMP"
```

### 10. Push and confirm the GitHub Verified badge

```bash
cd <your-org-repo>
git push
```

On GitHub, the commit should show a green **Verified** badge.

### 11. Tell the user what to do next

Summarize for the user:
- Which mode is now active (global / scoped)
- Where the key was saved (key ID + expiry)
- Where the scoped config file lives (if scoped)
- That `GPG_TTY` is in their shell rc — they need to open a new terminal or `source` the rc for the variable to take effect
- That the pinentry dialog will pop up on each commit until gpg-agent caches the passphrase (default cache: 10 minutes; max: 2 hours — configurable in `~/.gnupg/gpg-agent.conf`)

---

## Troubleshooting

- **"commit failed silently from IDE"** → pinentry not configured. Re-run step 3, then restart the IDE so it picks up the new gpg-agent.
- **"gpg: cannot open '/dev/tty': Device not configured"** → running gpg from a context without a controlling terminal (e.g. Claude's spawned bash, certain CI runners). Run the command in a real terminal session instead.
- **GitHub shows "Unverified" on a signed commit** → the GPG key's uid email doesn't match the commit's committer email. Check `git log -1 --format='%ae'` against `gpg --list-keys` output. Fix by setting `git config user.email` to the GPG-key email (or regenerate the key with the correct email).
- **"passphrase prompt loop"** → `GPG_TTY` isn't exported in the current shell. Run `export GPG_TTY=$(tty)` or open a new terminal so the rc-file export takes effect.
- **"Key expired"** → rotate yearly. `gpg --edit-key $KEY_ID` → `expire` → set new expiry → `save`, then re-upload to GitHub.
- **IDE still doesn't sign after pinentry is set up** → some IDEs cache the gpg-agent connection. Restart the IDE. As a last resort, `gpgconf --kill all` then restart the IDE.

## How to remove the setup later

**If global:**
```bash
git config --global --unset commit.gpgsign
git config --global --unset tag.gpgsign
git config --global --unset user.signingkey
```

**If scoped:**
```bash
git config --global --unset-all "includeIf.gitdir:$ORG_DIR/.path"
rm "$HOME/.gitconfig-<your-org>"
```

**To remove the key entirely:**
```bash
gpg --delete-secret-keys "$KEY_ID"
gpg --delete-keys "$KEY_ID"
# also revoke on GitHub: Settings → GPG keys → Delete
```

---

## Version

- Last updated: 2026-05-21
- Tested with: GnuPG ≥2.5, pinentry-mac ≥1.3
- Supported platforms: macOS, Linux (Debian/Ubuntu, Fedora/RHEL, Arch)
