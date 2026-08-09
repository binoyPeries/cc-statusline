#!/usr/bin/env bash
#
# cc-statusline — a status line for Claude Code
#
#   🤖 Opus 5 │ 🧠 51k/1M 5% │ ⏳ 5h 9% 4h32m │ 📅 7d 16% 2d
#
# Reads Claude Code's session JSON on stdin, writes one line to stdout.
# Compatible with bash 3.2 (macOS ships it), Linux, WSL and Git Bash.

set -u

CCSL_VERSION="1.0.0"

# ---------------------------------------------------------------------- config
# Override any of these via the environment, or in the config file below.

CCSL_CONFIG="${CCSL_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/cc-statusline/config.sh}"
# shellcheck disable=SC1090
[ -r "$CCSL_CONFIG" ] && . "$CCSL_CONFIG"

: "${CCSL_SEGMENTS:=model context five_hour seven_day}"
: "${CCSL_ICONS:=emoji}"    # emoji | nerd | unicode | none
: "${CCSL_COLOR:=auto}"     # auto | never
: "${CCSL_SEP:= │ }"
: "${CCSL_WARN:=60}"        # percent at which a meter turns yellow
: "${CCSL_CRIT_CTX:=75}"    # percent at which the context meter turns red
: "${CCSL_CRIT_LIMIT:=80}"  # percent at which a rate-limit meter turns red
: "${CCSL_LABEL:=default}"  # 5h ,7d label colors

# ----------------------------------------------------------------------- input modes
if [ "${1:-}" = "--version" ]; then echo "cc-statusline $CCSL_VERSION"; exit 0; fi 

if [ "${1:-}" = "--demo" ]; then # demo mode: no stdin, just show a sample line
  __now=$(date +%s)
  INPUT='{"model":{"id":"claude-opus-5","display_name":"Opus 5"},
  "context_window":{"context_window_size":1000000,"used_percentage":5,
    "current_usage":{"input_tokens":2,"output_tokens":393,
      "cache_creation_input_tokens":448,"cache_read_input_tokens":50552}},
  "rate_limits":{"five_hour":{"used_percentage":9,"resets_at":'$((__now+16320))'},
    "seven_day":{"used_percentage":16,"resets_at":'$((__now+193200))'}}}'
elif [ -t 0 ]; then
  echo "cc-statusline $CCSL_VERSION — expects Claude Code session JSON on stdin." >&2
  echo "Try: $0 --demo" >&2
  exit 64
else
  INPUT=$(cat)
fi

# ------------------------------------------------------------------ json parse
# TODO: need to check for windows and linux (jq not installed) scenarios.
parse() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$INPUT" | jq -r '
      def n: (if . == null then "" else . end) | tostring | @sh;
      (.context_window.current_usage // {}) as $u |
      "MODEL_ID=\(.model.id | n)",
      "MODEL_NAME=\(.model.display_name | n)",
      "CTX_USED=\((($u.input_tokens//0)+($u.output_tokens//0)
                  +($u.cache_creation_input_tokens//0)+($u.cache_read_input_tokens//0)) | n)",
      "CTX_SIZE=\(.context_window.context_window_size | n)",
      "CTX_PCT=\(.context_window.used_percentage | n)",
      "H5_PCT=\(.rate_limits.five_hour.used_percentage | n)",
      "H5_RESET=\(.rate_limits.five_hour.resets_at | n)",
      "D7_PCT=\(.rate_limits.seven_day.used_percentage | n)",
      "D7_RESET=\(.rate_limits.seven_day.resets_at | n)"
    ' 2>/dev/null && return 0
  fi

  # No jq on the box — parse with parameter expansion only.
  local flat obj cw cu h5 d7 tot v k
  flat=${INPUT//$'\n'/}
  scope() { REPLY=${flat#*\"$1\"*\{}; }
  num() { # $1 haystack, $2 key
    local s=${1#*\"$2\"} v
    case $s in "$1") REPLY=""; return;; esac
    s=${s#*:}; s=${s%%,*}; s=${s%%\}*}
    v=${s//[!0-9.-]/}; REPLY=$v
  }
  str() {
    local s=${flat#*\"$1\"}
    case $s in "$flat") REPLY=""; return;; esac
    s=${s#*\"}; REPLY=${s%%\"*}
  }
  scope context_window; cw=$REPLY
  scope current_usage;  cu=$REPLY
  scope five_hour;      h5=$REPLY
  scope seven_day;      d7=$REPLY
  tot=0
  for k in input_tokens output_tokens cache_creation_input_tokens cache_read_input_tokens; do
    num "$cu" "$k"; v=${REPLY%%.*}; tot=$(( tot + ${v:-0} ))
  done
  # Values are single-quoted: display names contain spaces.
  emit() { REPLY=${2//\'/\'\\\'\'}; echo "$1='$REPLY'"; }
  str id;           emit MODEL_ID "$REPLY"
  str display_name; emit MODEL_NAME "$REPLY"
  emit CTX_USED "$tot"
  num "$cw" context_window_size; emit CTX_SIZE "$REPLY"
  num "$cw" used_percentage;     emit CTX_PCT "$REPLY"
  num "$h5" used_percentage;     emit H5_PCT "$REPLY"
  num "$h5" resets_at;           emit H5_RESET "$REPLY"
  num "$d7" used_percentage;     emit D7_PCT "$REPLY"
  num "$d7" resets_at;           emit D7_RESET "$REPLY"
}

MODEL_ID=""; MODEL_NAME=""; CTX_USED=0; CTX_SIZE=""; CTX_PCT=""
H5_PCT=""; H5_RESET=""; D7_PCT=""; D7_RESET=""; REPLY=""
eval "$(parse)"

# Bash 5 exposes the clock as a variable; older shells pay for one `date`.
NOW=${EPOCHSECONDS:-}
[ -n "$NOW" ] || NOW=$(date +%s)

# ----------------------------------------------------------------------- style
if [ -n "${NO_COLOR:-}" ] || [ "$CCSL_COLOR" = never ]; then
  RST=""; GRAY=""; RED=""; GREEN=""; YELLOW=""
  BLUE=""; BBLUE=""; MAGENTA=""; CYAN=""; WHITE=""
else
  RST=$'\033[0m'
  RED=$'\033[31m';  GREEN=$'\033[32m';   YELLOW=$'\033[33m'
  BLUE=$'\033[34m'; MAGENTA=$'\033[35m'; CYAN=$'\033[36m'
  WHITE=$'\033[37m'; GRAY=$'\033[90m';   BBLUE=$'\033[94m'
fi

# Resolve CCSL_LABEL once. Anything unrecognised (including "default") leaves
# the label uncoloured, i.e. the terminal's own foreground.
case "$CCSL_LABEL" in
  red) LBL=$RED ;;         green) LBL=$GREEN ;;     yellow) LBL=$YELLOW ;;
  blue) LBL=$BLUE ;;       magenta) LBL=$MAGENTA ;; cyan) LBL=$CYAN ;;
  white) LBL=$WHITE ;;     gray|grey) LBL=$GRAY ;;
  *) LBL="" ;;
esac

case "$CCSL_ICONS" in
  emoji)   I_MODEL="🤖 "; I_CTX="🧠 "; I_5H="⏳ "; I_7D="📅 " ;;
  nerd)    I_MODEL="󰚩 ";  I_CTX="󰧑 ";  I_5H="󰥔 ";  I_7D="󰃭 "  ;;
  unicode) I_MODEL="◆ ";  I_CTX="▤ ";  I_5H="◷ ";  I_7D="▦ "  ;;
  *)       I_MODEL="";    I_CTX="";    I_5H="";    I_7D=""    ;;
esac

# --------------------------------------------------------------------- helpers

# A distinct hue per model family, so the model is identifiable at a glance.
# Green is deliberately absent: it means "healthy" on the meters, and reusing
# it for a model would make the two readings ambiguous.
model_color() {
  case "$MODEL_ID" in
    *opus*)   REPLY=$MAGENTA ;;
    *sonnet*) REPLY=$CYAN    ;;
    *haiku*)  REPLY=$BLUE    ;;
    *fable*)  REPLY=$BBLUE   ;;
    *mythos*) REPLY=$YELLOW  ;;
    *)        REPLY=$GRAY    ;;
  esac
}

# $1 = percentage, $2 = the red threshold (context and rate limits differ).
# Green below CCSL_WARN, yellow from there, red from $2 up.
percentage_color() {
  local p=${1%%.*}
  case ${p:-0} in ''|*[!0-9-]*) p=0 ;; esac
  if   [ "$p" -ge "$2" ];          then REPLY=$RED
  elif [ "$p" -ge "$CCSL_WARN" ];  then REPLY=$YELLOW
  else REPLY=$GREEN
  fi
}

# 51395 -> 51k ; 1000000 -> 1M  (rounded, no decimals)
ctx_size_formatter() {
  local n=${1%%.*}
  case ${n:-0} in ''|*[!0-9]*) n=0 ;; esac
  if   [ "$n" -ge 999500 ]; then REPLY="$(( (n + 500000) / 1000000 ))M"
  elif [ "$n" -ge 1000 ];   then REPLY="$(( (n + 500) / 1000 ))k"
  else REPLY="$n"
  fi
}

# Format a percentage with no decimal places, and append a percent sign.
percentage_formatter() { local p=${1:-0}; p=${p%.0}; REPLY="$p%"; }

# epoch seconds -> coarsest useful unit: "2d" over a day, else "5h40m", else "40m".
# Days floor rather than round, so the countdown never overstates what's left.
countdown() {
  local t=${1%%.*} s d m
  case ${t:-0} in ''|*[!0-9]*) t=0 ;; esac
  s=$(( t - NOW )); [ "$s" -lt 0 ] && s=0
  d=$(( s / 86400 )); m=$(( s % 3600 / 60 ))
  if   [ "$d" -gt 0 ];              then printf -v REPLY '%dd' "$d"
  elif [ "$(( s / 3600 ))" -gt 0 ]; then printf -v REPLY '%dh%02dm' "$(( s / 3600 ))" "$m"
  else printf -v REPLY '%dm' "$m"
  fi
}

# -------------------------------------------------------------------- segments
# Each appends to $LINE and returns 1 when its data isn't available.
LINE=""
add() { [ -n "$LINE" ] && LINE="$LINE$GRAY$CCSL_SEP$RST"; LINE="$LINE$1"; }

seg_model() {
  [ -n "$MODEL_NAME" ] || return 1
  model_color
  add "$I_MODEL$REPLY$MODEL_NAME$RST"
}

seg_context() {
  [ -n "$CTX_SIZE" ] && [ "${CTX_SIZE%%.*}" != 0 ] || return 1
  local used size pct c
  ctx_size_formatter "$CTX_USED"; used=$REPLY
  ctx_size_formatter "$CTX_SIZE"; size=$REPLY
  pct=$CTX_PCT
  if [ -z "$pct" ]; then pct=$(( CTX_USED * 100 / ${CTX_SIZE%%.*} )); fi
  local c
  percentage_color "$pct" "$CCSL_CRIT_CTX"; c=$REPLY
  percentage_formatter "$pct"
  add "$I_CTX$used/$size $c$REPLY$RST"
}

# Shared renderer for both rate-limit windows. Three visual levels: the label
# in CCSL_LABEL, the percentage in its status colour, the countdown in grey.
seg_limit() {
  local icon=$1 label=$2 pct=$3 reset=$4 out c
  [ -n "$pct" ] || return 1
  percentage_color "$pct" "$CCSL_CRIT_LIMIT"; c=$REPLY
  percentage_formatter "$pct"
  out="$icon$LBL$label$RST $c$REPLY$RST"
  if [ -n "$reset" ]; then countdown "$reset"; out="$out $GRAY$REPLY$RST"; fi
  add "$out"
}

seg_five_hour() { seg_limit "$I_5H" 5h "$H5_PCT" "$H5_RESET"; }
seg_seven_day() { seg_limit "$I_7D" 7d "$D7_PCT" "$D7_RESET"; }

# ---------------------------------------------------------------------- render
for s in $CCSL_SEGMENTS; do
  case " model context five_hour seven_day " in
    *" $s "*) "seg_$s" || : ;;
  esac
done

printf '%s' "$LINE"
