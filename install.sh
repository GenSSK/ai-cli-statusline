#!/usr/bin/env bash
# ai-cli-statusline installer (macOS / Linux / WSL / Windows Git Bash)
#
#   curl -fsSL https://raw.githubusercontent.com/GenSSK/ai-cli-statusline/main/install.sh | bash
#
# Options (pass after `bash -s --`):
#   --no-claude   Skip Claude Code
#   --no-codex    Skip Codex CLI
set -euo pipefail

# Windows (Git Bash): jq.exe prints CRLF line endings; strip the CR.
case "$OSTYPE" in
  msys*|cygwin*) jq() { command jq "$@" | tr -d '\r'; return "${PIPESTATUS[0]}"; } ;;
esac
REPO_RAW="https://raw.githubusercontent.com/GenSSK/ai-cli-statusline/main"
DO_CLAUDE=1
DO_CODEX=1
for arg in "$@"; do
  case "$arg" in
    --no-claude) DO_CLAUDE=0 ;;
    --no-codex)  DO_CODEX=0 ;;
    -h|--help)   sed -n '2,9p' "$0" 2>/dev/null || true; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [ -t 1 ]; then
  B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'
else
  B=""; G=""; Y=""; R=""; N=""
fi
info() { printf '%s==>%s %s\n' "$B" "$N" "$*"; }
ok()   { printf '%s ✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '%s !%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '%s ✗%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

# ---------- Platform ----------
case "$(uname -s)" in
  Darwin) OS=macos ;;
  Linux)  if grep -qi microsoft /proc/version 2>/dev/null; then OS=wsl; else OS=linux; fi ;;
  MINGW*|MSYS*|CYGWIN*) OS=windows ;;
  *) OS=unknown ;;
esac
info "Platform: $OS"

# Convert a Windows path (C:\...) to a POSIX path for Git Bash
to_posix() {
  if [ "$OS" = windows ] && command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; else printf '%s' "$1"; fi
}

jq_hint() {
  case "$OS" in
    macos)   echo "brew install jq" ;;
    windows) echo "winget install jqlang.jq   (then reopen the terminal)" ;;
    *)       echo "sudo apt install jq   /   sudo dnf install jq   /   sudo pacman -S jq" ;;
  esac
}

# ---------- Fetch a repo file (local clone or GitHub) ----------
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi
fetch() {  # fetch <repo path> <dest>
  if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/$1" ]; then
    cp "$SCRIPT_DIR/$1" "$2"
  else
    curl -fsSL "$REPO_RAW/$1" -o "$2"
  fi
}

backup() {  # backup <file> -> prints backup path
  local b
  b="$1.bak-$(date +%Y%m%d%H%M%S)"
  cp -p "$1" "$b"
  printf '%s' "$b"
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ---------- Claude Code ----------
install_claude() {
  info "Claude Code"
  command -v jq >/dev/null 2>&1 || die "jq is required. Install it with:  $(jq_hint)"
  command -v curl >/dev/null 2>&1 || die "curl is required."

  local dir="${CLAUDE_CONFIG_DIR:-}"
  local cmd
  if [ -n "$dir" ]; then
    dir=$(to_posix "$dir")
    if [ "$OS" = windows ] && command -v cygpath >/dev/null 2>&1; then
      cmd="bash \"$(cygpath -m "$dir")/statusline.sh\""
    else
      cmd="bash \"$dir/statusline.sh\""
    fi
  else
    dir="$HOME/.claude"
    cmd="bash ~/.claude/statusline.sh"
  fi
  mkdir -p "$dir"

  # Script
  fetch claude/statusline.sh "$TMP/statusline.sh"
  if [ -f "$dir/statusline.sh" ] && ! cmp -s "$TMP/statusline.sh" "$dir/statusline.sh"; then
    ok "Backed up existing script -> $(backup "$dir/statusline.sh")"
  fi
  cp "$TMP/statusline.sh" "$dir/statusline.sh"
  chmod +x "$dir/statusline.sh"
  ok "Installed $dir/statusline.sh"

  # settings.json
  local settings="$dir/settings.json"
  if [ -f "$settings" ]; then
    jq -e . "$settings" >/dev/null 2>&1 || die "$settings is not valid JSON. Fix it and re-run."
    if [ "$(jq -r '.statusLine.command // ""' "$settings")" = "$cmd" ]; then
      ok "settings.json already configured"
      return
    fi
    ok "Backed up settings.json -> $(backup "$settings")"
  else
    echo '{}' > "$settings"
  fi
  jq --arg cmd "$cmd" '.statusLine = ((.statusLine // {}) + {type: "command", command: $cmd})' \
    "$settings" > "$TMP/settings.json"
  cp "$TMP/settings.json" "$settings"
  ok "Set statusLine in $settings"
}

# ---------- Codex CLI ----------
install_codex() {
  local dir
  dir=$(to_posix "${CODEX_HOME:-$HOME/.codex}")
  if [ ! -d "$dir" ] && ! command -v codex >/dev/null 2>&1; then
    info "Codex CLI not found — skipped"
    return
  fi
  info "Codex CLI"
  mkdir -p "$dir"
  local conf="$dir/config.toml"
  local items='status_line = ["model-with-reasoning", "fast-mode", "context-used", "estimated-thread-cost", "five-hour-limit", "weekly-limit", "git-branch", "current-dir"]'
  local colors='status_line_use_colors = true'

  if [ -f "$conf" ]; then
    # Is status_line already set inside [tui]?
    if grep -Fxq "$items" "$conf"; then
      ok "config.toml already configured"
      return
    fi
    if awk '/^[[:space:]]*\[/ { t = $0; gsub(/[[:space:]]/, "", t) } t == "[tui]" && /^[[:space:]]*status_line[[:space:]]*=/ { f = 1 } END { exit !f }' "$conf"; then
      warn "status_line is already set in $conf — left unchanged."
      warn "To use this setup, replace it with the [tui] keys from codex/config.toml."
      return
    fi
    ok "Backed up config.toml -> $(backup "$conf")"
    if grep -Eq '^[[:space:]]*\[tui\][[:space:]]*(#.*)?$' "$conf"; then
      awk -v a="$items" -v b="$colors" '
        { print }
        !done && /^[[:space:]]*\[tui\][[:space:]]*(#.*)?$/ { print a; print b; done = 1 }
      ' "$conf" > "$TMP/config.toml"
    else
      { cat "$conf"; printf '\n[tui]\n%s\n%s\n' "$items" "$colors"; } > "$TMP/config.toml"
    fi
    cp "$TMP/config.toml" "$conf"
  else
    printf '[tui]\n%s\n%s\n' "$items" "$colors" > "$conf"
  fi
  ok "Set [tui].status_line in $conf"
}

[ "$DO_CLAUDE" = 1 ] && install_claude
[ "$DO_CODEX" = 1 ] && install_codex

echo
ok "Done. Restart Claude Code / Codex to see the new status line."
