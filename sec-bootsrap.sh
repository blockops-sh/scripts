#!/usr/bin/env bash
set -euo pipefail

# ==================================================
# Enterprise Pre-commit Global Bootstrap
# ==================================================
# - Cross-platform (macOS + Linux)
# - Idempotent (safe to re-run)
# - Global Git hooks enforcement
# - Repo override supported
# - Secure baseline (gitleaks)
# ==================================================

HOOKS_DIR="$HOME/.githooks"
CONFIG_DIR="$HOME/.config/pre-commit/v1"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
CACHE_DIR="$HOME/.cache/pre-commit"
LOG_FILE="$HOME/.bootstrap-precommit.log"

# -----------------------------
# Logging helpers
# -----------------------------
info() { echo "[INFO] $1" | tee -a "$LOG_FILE"; }
warn() { echo "[WARN] $1" | tee -a "$LOG_FILE"; }
err()  { echo "[ERROR] $1" | tee -a "$LOG_FILE"; }

# -----------------------------
# OS Detection
# -----------------------------
detect_os() {
  case "$(uname -s)" in
    Darwin) OS="macos" ;;
    Linux)  OS="linux" ;;
    *) err "Unsupported OS"; exit 1 ;;
  esac
  info "Detected OS: $OS"
}

# -----------------------------
# Install pre-commit
# -----------------------------
install_precommit() {
  if command -v pre-commit >/dev/null 2>&1; then
    info "pre-commit already installed"
    return
  fi

  if command -v pipx >/dev/null 2>&1; then
    pipx install pre-commit
  elif command -v pip >/dev/null 2>&1; then
    pip install --user pre-commit
  else
    err "pip or pipx required to install pre-commit"
    exit 1
  fi
}

# -----------------------------
# Install gitleaks (binary)
# -----------------------------
install_gitleaks() {
  if command -v gitleaks >/dev/null 2>&1; then
    info "gitleaks already installed"
    return
  fi

  VERSION="8.30.1"
  TMP_DIR="$(mktemp -d)"

  if [ "$OS" = "macos" ]; then
    case "$(uname -m)" in
      arm64|aarch64) ARCH="arm64" ;;
      x86_64|amd64)  ARCH="x64" ;;
      *) err "Unsupported macOS arch: $(uname -m)"; exit 1 ;;
    esac
    FILE="gitleaks_${VERSION}_darwin_${ARCH}.tar.gz"
  else
    FILE="gitleaks_${VERSION}_linux_x64.tar.gz"
  fi

  URL="https://github.com/gitleaks/gitleaks/releases/download/v${VERSION}/${FILE}"

  info "Downloading gitleaks..."
  curl -sSL "$URL" -o "$TMP_DIR/gitleaks.tar.gz"

  tar -xzf "$TMP_DIR/gitleaks.tar.gz" -C "$TMP_DIR"

  chmod +x "$TMP_DIR/gitleaks"

  if [ -w "/usr/local/bin" ]; then
    mv "$TMP_DIR/gitleaks" /usr/local/bin/
  else
    mkdir -p "$HOME/.local/bin"
    mv "$TMP_DIR/gitleaks" "$HOME/.local/bin/"
    export PATH="$HOME/.local/bin:$PATH"
  fi

  rm -rf "$TMP_DIR"

  info "gitleaks installed"
}

# -----------------------------
# Setup global git hooks
# -----------------------------
setup_git_hooks() {
  mkdir -p "$HOOKS_DIR"
  git config --global core.hooksPath "$HOOKS_DIR"
  info "Configured global hooks path -> $HOOKS_DIR"
}

# -----------------------------
# Global pre-commit config
# -----------------------------
setup_global_config() {
  mkdir -p "$CONFIG_DIR"

  cat > "$CONFIG_FILE" << 'EOF'
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: check-merge-conflict
      - id: check-case-conflict
      - id: check-executables-have-shebangs
      - id: check-shebang-scripts-are-executable
      - id: check-yaml
      - id: check-toml
      - id: check-json
      - id: end-of-file-fixer
      - id: trailing-whitespace
      - id: mixed-line-ending
      - id: check-added-large-files
        args: ["--maxkb=1024"]

  - repo: local
    hooks:
      - id: gitleaks
        name: gitleaks (staged)
        entry: gitleaks git --staged --redact --no-banner
        language: system
        pass_filenames: false
EOF

  info "Global config written -> $CONFIG_FILE"
}

# -----------------------------
# Global hook script
# -----------------------------
setup_hook_script() {
  cat > "$HOOKS_DIR/pre-commit" << 'EOF'
#!/bin/sh
set -eu

export PRE_COMMIT_HOME="$HOME/.cache/pre-commit"

if ! command -v pre-commit >/dev/null 2>&1; then
  echo "[pre-commit] not installed. Skipping."
  exit 0
fi

# Skip if no staged changes (fast path)
if git diff --cached --quiet; then
  echo "[pre-commit] No staged changes"
  exit 0
fi

if [ -f ".pre-commit-config.yaml" ]; then
  echo "[pre-commit] Using repo config"
  exec pre-commit run --hook-stage commit --show-diff-on-failure
fi

GLOBAL_CONFIG="$HOME/.config/pre-commit/v1/config.yaml"
if [ -f "$GLOBAL_CONFIG" ]; then
  echo "[pre-commit] Using global config (v1)"
  exec pre-commit run --hook-stage commit --show-diff-on-failure --config "$GLOBAL_CONFIG"
fi

exit 0
EOF

  chmod +x "$HOOKS_DIR/pre-commit"
  info "Global hook installed"
}

# -----------------------------
# Verify
# -----------------------------
verify() {
  info "Verifying setup..."

  git config --global --get core.hooksPath | grep -q "$HOOKS_DIR" \
    && info "Git hooks path OK" || warn "Git hooks path NOT set"

  command -v pre-commit >/dev/null 2>&1 && info "$(pre-commit --version)"
  command -v gitleaks >/dev/null 2>&1 && info "gitleaks installed"
}

# -----------------------------
# Main
# -----------------------------
main() {
  detect_os
  install_precommit
  install_gitleaks
  setup_git_hooks
  setup_global_config
  setup_hook_script
  verify

  info "Bootstrap complete"
}

main "$@"

# hook-smoke-test 20260408T085132Z
