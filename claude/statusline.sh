#!/bin/bash
# Claude Code statusline script (improved)
# Line 1: Model vVersion [effort] │ [context bar] XX% (used/total) │ $cost │ +added -removed
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
#
# Environment variables (optional):
#   STATUSLINE_TZ=Asia/Tokyo   Time zone for reset times (default: system time zone)
#   STATUSLINE_PROBE=0         Disable the Haiku probe fallback (no network access)
#   STATUSLINE_CACHE_FILE=...  Cache path (default: /tmp/claude-statusline-ratelimits.json)

# Windows (Git Bash): jq.exe prints CRLF line endings; strip the CR.
case "$OSTYPE" in
  msys*|cygwin*) jq() { command jq "$@" | tr -d '\r'; return "${PIPESTATUS[0]}"; } ;;
esac
input=$(cat)
now=$(date +%s)
[ -n "$STATUSLINE_TZ" ] && export TZ="$STATUSLINE_TZ"

# ---------- Extract data (single jq call) ----------
# The @sh filter quotes every value, so eval is safe.
eval "$(echo "$input" | jq -r '
  "model=" + (.model.display_name // "Unknown" | @sh),
  "version=" + (.version // "" | @sh),
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
