#!/bin/bash
# Claude Code statusline script (improved)
# Line 1: Model vVersion [effort] │ [context bar] XX% (used/total) │ $cost │ +added -removed │ session_id
# Line 2: 5h rate limit progress bar
# Line 3: 7d rate limit progress bar
#
# Changes from statusline.orig.sh:
#   - Rate limits are read from stdin `.rate_limits` (Claude Code official field).
#     The Haiku probe is used only as a fallback when that field is absent
#     (e.g. before the first API response of a session).
#   - Percentages are clamped to 0-100.
#   - Cached values whose window has already reset are discarded.
#   - 0% is shown as 0% (previously shown as --%).
#   - effort level / fast mode are shown on line 1.
#   - session ID is shown on line 1 (after +added -removed).
#
# Environment variables (optional):
#   STATUSLINE_TZ=Asia/Tokyo   Time zone for reset times (default: system time zone)
#   STATUSLINE_PROBE=0         Disable the Haiku probe fallback (no network access)
#   STATUSLINE_CACHE_FILE=...  Cache path (default: /tmp/claude-statusline-ratelimits.json)
#   STATUSLINE_RIGHT_MARGIN=4  Right margin (columns) for the directory on line 1

# Windows (Git Bash): jq.exe prints CRLF line endings; strip the CR.
# A jq installed by winget is missing from PATH when Claude Code was started
# from a terminal opened before the install, so look in winget's folders too.
case "$OSTYPE" in
  msys*|cygwin*)
    if ! command -v jq >/dev/null 2>&1 && [ -n "$LOCALAPPDATA" ]; then
      winget_dir=$(cygpath -u "$LOCALAPPDATA" 2>/dev/null)/Microsoft/WinGet
      for d in "$winget_dir/Links" "$winget_dir"/Packages/jqlang.jq_*; do
        [ -x "$d/jq.exe" ] && { PATH="$PATH:$d"; break; }
      done
    fi
    jq() { command jq "$@" | tr -d '\r'; return "${PIPESTATUS[0]}"; } ;;
esac
input=$(cat)
now=$(date +%s)
[ -n "$STATUSLINE_TZ" ] && export TZ="$STATUSLINE_TZ"

# ---------- Extract data (single jq call) ----------
# The @sh filter quotes every value, so eval is safe.
eval "$(echo "$input" | jq -r '
  "model=" + (.model.display_name // "Unknown" | @sh),
  "version=" + (.version // "" | @sh),
  "cwd=" + (.workspace.current_dir // .cwd // "" | @sh),
  "context_size=" + (.context_window.context_window_size // 200000 | tostring | @sh),
  "used_pct=" + (.context_window.used_percentage // 0 | tostring | @sh),
  "input_tokens=" + ((.context_window.current_usage // {}) as $u
      | if $u.input_tokens == null then "" else
          (($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.cache_read_input_tokens // 0)) | tostring
        end | @sh),
  "cost=" + (.cost.total_cost_usd // 0 | tostring | @sh),
  "added=" + (.cost.total_lines_added // 0 | tostring | @sh),
  "removed=" + (.cost.total_lines_removed // 0 | tostring | @sh),
  "effort=" + (.effort.level // "" | @sh),
  "fast_mode=" + (.fast_mode // false | tostring | @sh),
  "session_id=" + (.session_id // "" | @sh),
  "IN_5H_PCT=" + (.rate_limits.five_hour.used_percentage // "" | tostring | @sh),
  "IN_5H_RESET=" + (.rate_limits.five_hour.resets_at // "" | tostring | @sh),
  "IN_7D_PCT=" + (.rate_limits.seven_day.used_percentage // "" | tostring | @sh),
  "IN_7D_RESET=" + (.rate_limits.seven_day.resets_at // "" | tostring | @sh)
' 2>/dev/null)"
cc_version="${version:-0.0.0}"

# Clamp a number to [0, 100] and round to an integer. Empty in -> empty out.
clamp_pct() {
  local v="$1"
  [ -z "$v" ] || [ "$v" = "null" ] && { echo ""; return; }
  awk -v v="$v" 'BEGIN { if (v !~ /^-?[0-9.eE+-]+$/) exit; if (v < 0) v = 0; if (v > 100) v = 100; printf "%d", v + 0.5 }'
}

fmt() {
  local n=$1
  if [ "$n" -ge 1000000 ] 2>/dev/null; then
    awk "BEGIN {printf \"%.1fM\", $n/1000000}"
  elif [ "$n" -ge 1000 ] 2>/dev/null; then
    awk "BEGIN {printf \"%.1fk\", $n/1000}"
  else
    echo "${n:-0}"
  fi
}

reset="\033[0m"

# ---------- Line 1 ----------
pct_int=$(clamp_pct "$used_pct"); pct_int=${pct_int:-0}
if [ -n "$input_tokens" ]; then
  current_used=$input_tokens
else
  current_used=$(awk "BEGIN {printf \"%.0f\", ($pct_int * $context_size) / 100}")
fi

filled=$((pct_int / 10))
empty=$((10 - filled))
bar=""
for ((i=0; i<filled; i++)); do bar+="█"; done
for ((i=0; i<empty; i++)); do bar+="░"; done

if [ "$pct_int" -ge 80 ]; then
  color="\033[31m"
elif [ "$pct_int" -ge 50 ]; then
  color="\033[33m"
else
  color="\033[32m"
fi

cost_str=$(awk "BEGIN {printf \"\$%.4f\", $cost}")

model_str="$model${version:+ v$version}"
[ -n "$effort" ] && model_str+=" \033[2m[${effort}]\033[0m"
[ "$fast_mode" = "true" ] && model_str+=" \033[35m⚡fast\033[0m"

line1=$(printf "%b │ ${color}%s %d%%${reset} (%s/%s) │ %s │ +%d -%d" \
  "$model_str" "$bar" "$pct_int" \
  "$(fmt $current_used)" "$(fmt $context_size)" \
  "$cost_str" "$added" "$removed")
[ -n "$session_id" ] && line1+=$(printf " │ \033[2m%s${reset}" "$session_id")

# ---------- Current directory (fish style, right-aligned on line 1) ----------
# ~/ai-global/status_line -> ~/a/status_line  (dot dirs keep 2 chars: ~/.c/fish)
fish_path() {
  local LC_ALL=C   # byte-wise string ops; multibyte chars are handled below
  local p="${1//\\//}" home h out="" i n b
  for home in "$HOME" "$(command -v cygpath >/dev/null 2>&1 && cygpath -m "$HOME")"; do
    [ -z "$home" ] && continue
    case "$p" in
      "$home") p="~"; break ;;
      "$home"/*) p="~${p#"$home"}"; break ;;
    esac
  done
  local IFS=/
  local -a parts
  read -r -a parts <<< "$p"
  [ "${p:0:1}" = "/" ] && out="/"
  n=${#parts[@]}
  for ((i = 0; i < n; i++)); do
    local part="${parts[$i]}"
    [ -z "$part" ] && continue
    if [ "$i" -lt $((n - 1)) ]; then
      local lead=""
      if [ "${part:0:1}" = "." ]; then lead="."; part="${part:1}"; fi
      # first character = 1-4 bytes depending on the UTF-8 lead byte
      b=$(printf '%d' "'${part:0:1}")
      [ "$b" -lt 0 ] && b=$((b + 256))
      if   [ "$b" -ge 240 ]; then part="${part:0:4}"
      elif [ "$b" -ge 224 ]; then part="${part:0:3}"
      elif [ "$b" -ge 192 ]; then part="${part:0:2}"
      else part="${part:0:1}"; fi
      out+="${lead}${part}/"
    else
      out+="$part"
    fi
  done
  printf '%s' "${out:-/}"
}

# Display width: ASCII = 1, 2-byte UTF-8 = 1, 3/4-byte (CJK, emoji) = 2
str_width() {
  local s n1 n2 n34
  s=$(printf '%s' "$1" | LC_ALL=C sed $'s/\x1b\\[[0-9;]*m//g')
  n1=$(printf '%s' "$s" | LC_ALL=C tr -d '\200-\377' | wc -c)
  n2=$(printf '%s' "$s" | LC_ALL=C tr -cd '\300-\337' | wc -c)
  n34=$(printf '%s' "$s" | LC_ALL=C tr -cd '\340-\367' | wc -c)
  echo $(( n1 + n2 + 2 * n34 ))
}

if [ -n "$cwd" ]; then
  dir_str=$(fish_path "$cwd")
  # Sky blue: parents in a deeper blue, current dir in bold sky blue (256 colors)
  case "$dir_str" in
    */?*) dir_parent="${dir_str%/*}/"; dir_last="${dir_str##*/}" ;;
    *)    dir_parent=""; dir_last="$dir_str" ;;
  esac
  dir_fmt="\033[38;5;74m${dir_parent//%/%%}\033[1;38;5;117m${dir_last//%/%%}${reset}"
  if [ -n "$COLUMNS" ] && [ "$COLUMNS" -gt 0 ] 2>/dev/null; then
    # Line 1 is box-drawing chars (width 1) + ASCII, plus ⚡ (width 2) in fast mode
    w1=$(printf '%s' "$line1" | LC_ALL=C sed $'s/\x1b\\[[0-9;]*m//g' | LC_ALL=C tr -d '\200-\277' | wc -c)
    [ "$fast_mode" = "true" ] && w1=$((w1 + 1))
    gap=$(( COLUMNS - ${STATUSLINE_RIGHT_MARGIN:-4} - w1 - $(str_width "$dir_str") ))
    if [ "$gap" -ge 2 ]; then
      line1+=$(printf "%${gap}s${dir_fmt}" "")
    fi
  else
    line1+=$(printf " │ ${dir_fmt}")
  fi
fi

# ---------- Rate limits ----------
# Priority: stdin .rate_limits > cache (window not yet reset) > Haiku probe
# Cache stores percentages (0-100) and reset epochs.
CACHE_FILE="${STATUSLINE_CACHE_FILE:-/tmp/claude-statusline-ratelimits.json}"
PROBE_TTL=360
FIVE_HOUR_PCT=""; FIVE_HOUR_RESET=""
SEVEN_DAY_PCT=""; SEVEN_DAY_RESET=""

save_cache() {
  jq -n \
    --arg h5p "$1" --arg h5r "$2" --arg h7p "$3" --arg h7r "$4" --arg src "$5" \
    '{five_pct: $h5p, five_reset: $h5r, seven_pct: $h7p, seven_reset: $h7r, source: $src}' \
    > "$CACHE_FILE.$$" 2>/dev/null && mv -f "$CACHE_FILE.$$" "$CACHE_FILE"
}

load_cache() {
  [ -f "$CACHE_FILE" ] || return 1
  eval "$(jq -r '
    "C5P=" + (.five_pct // "" | @sh),
    "C5R=" + (.five_reset // "" | @sh),
    "C7P=" + (.seven_pct // "" | @sh),
    "C7R=" + (.seven_reset // "" | @sh)
  ' "$CACHE_FILE" 2>/dev/null)"
  # Discard windows that have already reset (value belongs to the old window)
  if [ -n "$C5R" ] && [ "$C5R" -gt "$now" ] 2>/dev/null; then
    FIVE_HOUR_PCT="$C5P"; FIVE_HOUR_RESET="$C5R"
  fi
  if [ -n "$C7R" ] && [ "$C7R" -gt "$now" ] 2>/dev/null; then
    SEVEN_DAY_PCT="$C7P"; SEVEN_DAY_RESET="$C7R"
  fi
  [ -n "$FIVE_HOUR_PCT$SEVEN_DAY_PCT" ]
}

fetch_usage() {
  local access_token
  # macOS: Keychain経由
  if command -v security >/dev/null 2>&1; then
    local token
    token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || true)
    if [ -n "$token" ]; then
      if echo "$token" | jq -e . >/dev/null 2>&1; then
        access_token=$(echo "$token" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
      else
        access_token="$token"
      fi
    fi
  fi
  # Linux: ~/.claude/.credentials.json から取得
  if [ -z "$access_token" ] && [ -f "$HOME/.claude/.credentials.json" ]; then
    access_token=$(jq -r '.claudeAiOauth.accessToken // empty' "$HOME/.claude/.credentials.json" 2>/dev/null)
  fi
  [ -z "$access_token" ] && return 1

  local headers
  headers=$(curl -sD- --max-time 8 -o /dev/null \
    -H "Authorization: Bearer ${access_token}" \
    -H "Content-Type: application/json" \
    -H "User-Agent: claude-code/${cc_version}" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "anthropic-version: 2023-06-01" \
    -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"h"}]}' \
    "https://api.anthropic.com/v1/messages" 2>/dev/null || true)
  [ -z "$headers" ] && return 1

  hdr() { echo "$headers" | grep -i "anthropic-ratelimit-unified-$1" | head -1 | tr -d '\r' | awk '{print $2}'; }
  local h5u h5r h7u h7r
  h5u=$(hdr 5h-utilization); h5r=$(hdr 5h-reset)
  h7u=$(hdr 7d-utilization); h7r=$(hdr 7d-reset)
  [ -z "$h5u" ] && return 1

  # utilization header is a 0-1 ratio (may exceed 1) -> percentage
  to_pct() { [ -n "$1" ] && awk -v v="$1" 'BEGIN{printf "%.1f", v * 100}'; }
  FIVE_HOUR_PCT=$(to_pct "$h5u"); FIVE_HOUR_RESET="$h5r"
  SEVEN_DAY_PCT=$(to_pct "$h7u"); SEVEN_DAY_RESET="$h7r"
  save_cache "$FIVE_HOUR_PCT" "$FIVE_HOUR_RESET" "$SEVEN_DAY_PCT" "$SEVEN_DAY_RESET" probe
  return 0
}

cache_age() {
  [ -f "$CACHE_FILE" ] || { echo 999999; return; }
  echo $(( now - $(stat -c '%Y' "$CACHE_FILE" 2>/dev/null || stat -f '%m' "$CACHE_FILE" 2>/dev/null || echo 0) ))
}

if [ -n "$IN_5H_PCT$IN_7D_PCT" ]; then
  FIVE_HOUR_PCT="$IN_5H_PCT"; FIVE_HOUR_RESET="$IN_5H_RESET"
  SEVEN_DAY_PCT="$IN_7D_PCT"; SEVEN_DAY_RESET="$IN_7D_RESET"
  save_cache "$FIVE_HOUR_PCT" "$FIVE_HOUR_RESET" "$SEVEN_DAY_PCT" "$SEVEN_DAY_RESET" stdin
elif [ "$(cache_age)" -lt "$PROBE_TTL" ] && load_cache; then
  :
elif [ "${STATUSLINE_PROBE:-1}" != "0" ] && fetch_usage; then
  :
else
  load_cache
fi

FIVE_HOUR_PCT=$(clamp_pct "$FIVE_HOUR_PCT")
SEVEN_DAY_PCT=$(clamp_pct "$SEVEN_DAY_PCT")

# ---------- Progress bar for rate limits (10 segments) ----------
rate_bar() {
  local pct="$1"
  local filled=$(( (pct + 5) / 10 ))
  [ "$filled" -gt 10 ] && filled=10
  local bar=""
  for ((i=0; i<filled; i++)); do bar+="▰"; done
  for ((i=filled; i<10; i++)); do bar+="▱"; done
  echo "$bar"
}

rate_color() {
  local pct="$1"
  if [ "$pct" -ge 80 ]; then
    echo "\033[31m"
  elif [ "$pct" -ge 50 ]; then
    echo "\033[33m"
  else
    echo "\033[32m"
  fi
}

format_epoch_time() {
  local epoch="$1"
  local format="$2"
  { [ -z "$epoch" ] || [ "$epoch" = "0" ]; } && return

  local formatted_date
  if date --version >/dev/null 2>&1; then
    # GNU date (Linux)
    formatted_date=$(date -d "@${epoch}" "$format" 2>/dev/null)
  else
    # BSD date (macOS)
    formatted_date=$(date -j -f "%s" "$epoch" "$format" 2>/dev/null)
  fi

  echo "$formatted_date" | sed 's/AM/am/;s/PM/pm/'
}

rate_line() {
  local icon="$1" label="$2" pct="$3" reset_epoch="$4" reset_fmt="$5"
  if [ -z "$pct" ]; then
    echo "\033[90m${icon} ${label}  ▱▱▱▱▱▱▱▱▱▱  --%\033[0m"
    return
  fi
  local reset_display=""
  if [ -n "$reset_epoch" ] && [ "$reset_epoch" != "0" ]; then
    reset_display=" \033[2mResets $(format_epoch_time "$reset_epoch" "$reset_fmt")\033[0m"
  fi
  echo "$(rate_color "$pct")${icon} ${label}  $(rate_bar "$pct")  ${pct}%${reset}${reset_display}"
}

line2=$(rate_line "⏱" "5h" "$FIVE_HOUR_PCT" "$FIVE_HOUR_RESET" "+%-I:%M%p %Z")
line3=$(rate_line "📅" "7d" "$SEVEN_DAY_PCT" "$SEVEN_DAY_RESET" "+%b %-d at %-I%p %Z")

# ---------- Output ----------
echo -e "$line1"
echo -e "$line2"
echo -e -n "$line3"
