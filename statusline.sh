#!/usr/bin/env bash
#
# cc-statusline — a status line for Claude Code
#
#   🤖 Opus 5 (high) │ 🧠 5% 51k/1M │ ⏳ 5h 9% 4h32m │ 📅 7d 16% 2d
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
: "${CCSL_EFFORT:=auto}"    # auto | never — effort rides along with the model
: "${CCSL_ICONS:=emoji}"    # emoji | nerd | unicode | none
: "${CCSL_COLOR:=auto}"     # auto | never
: "${CCSL_SEP:= │ }"
: "${CCSL_WARN:=60}"        # percent at which a meter turns yellow
: "${CCSL_CRIT_CTX:=75}"    # percent at which the context meter turns red
: "${CCSL_CRIT_LIMIT:=80}"  # percent at which a rate-limit meter turns red

# ----------------------------------------------------------------------- input modes
if [ "${1:-}" = "--version" ]; then echo "cc-statusline $CCSL_VERSION"; exit 0; fi 

if [ "${1:-}" = "--demo" ]; then # demo mode: no stdin, just show a sample line
  __now=$(date +%s)
  INPUT='{"model":{"id":"claude-fable-5","display_name":"Mythos 5"},
  "effort":{"level":"high"},
  "context_window":{"context_window_size":1000000,"used_percentage":5.1767338,
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
      "EFFORT=\(.effort.level | n)",
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
  local flat obj cw cu h5 d7 ef tot v k
  flat=${INPUT//$'\n'/}
  # Empty rather than the whole document when the object is absent, so the
  # getters below can't wander off into a neighbouring object's keys.
  scope() { REPLY=${flat#*\"$1\"*\{}; case $REPLY in "$flat") REPLY="" ;; esac; }
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
  sstr() { # $1 haystack, $2 key — str(), scoped to one object
    local s=${1#*\"$2\"}
    case $s in "$1") REPLY=""; return;; esac
    s=${s#*\"}; REPLY=${s%%\"*}
  }
  scope context_window; cw=$REPLY
  scope current_usage;  cu=$REPLY
  scope five_hour;      h5=$REPLY
  scope seven_day;      d7=$REPLY
  scope effort;         ef=$REPLY
  tot=0
  for k in input_tokens output_tokens cache_creation_input_tokens cache_read_input_tokens; do
    num "$cu" "$k"; v=${REPLY%%.*}; tot=$(( tot + ${v:-0} ))
  done
  # Values are single-quoted: display names contain spaces.
  emit() { REPLY=${2//\'/\'\\\'\'}; echo "$1='$REPLY'"; }
  str id;           emit MODEL_ID "$REPLY"
  str display_name; emit MODEL_NAME "$REPLY"
  sstr "$ef" level; emit EFFORT "$REPLY"
  emit CTX_USED "$tot"
  num "$cw" context_window_size; emit CTX_SIZE "$REPLY"
  num "$cw" used_percentage;     emit CTX_PCT "$REPLY"
  num "$h5" used_percentage;     emit H5_PCT "$REPLY"
  num "$h5" resets_at;           emit H5_RESET "$REPLY"
  num "$d7" used_percentage;     emit D7_PCT "$REPLY"
  num "$d7" resets_at;           emit D7_RESET "$REPLY"
}

MODEL_ID=""; MODEL_NAME=""; EFFORT=""; CTX_USED=0; CTX_SIZE=""; CTX_PCT=""
H5_PCT=""; H5_RESET=""; D7_PCT=""; D7_RESET=""; REPLY=""
eval "$(parse)"

# Bash 5 exposes the clock as a variable; older shells pay for one `date`.
NOW=${EPOCHSECONDS:-}
[ -n "$NOW" ] || NOW=$(date +%s)

# ----------------------------------------------------------------------- style
# 16-colour SGR only: the terminal resolves each code against its own theme, so
# there is no light/dark palette to pick. Hue travels safely between themes but
# lightness does not, hence DIM for chrome rather than a fixed grey.
if [ -n "${NO_COLOR:-}" ] || [ "$CCSL_COLOR" = never ]; then
  RST=""; DIM=""; RED=""; GREEN=""; YELLOW=""
  BLUE=""; BBLUE=""; MAGENTA=""; CYAN=""
else
  RST=$'\033[0m'
  DIM=$'\033[2m'                                            # chrome
  RED=$'\033[31m';  GREEN=$'\033[32m';   YELLOW=$'\033[33m' # status
  BLUE=$'\033[34m'; MAGENTA=$'\033[35m'; CYAN=$'\033[36m'   # identity
  BBLUE=$'\033[94m'
fi

case "$CCSL_ICONS" in
  emoji)   I_MODEL="🤖 "; I_CTX="🧠 "; I_5H="⏳ "; I_7D="📅 " ;;
  nerd)    I_MODEL="󰚩 ";  I_CTX="󰧑 ";  I_5H="󰥔 ";  I_7D="󰃭 "  ;;
  unicode) I_MODEL="◆ ";  I_CTX="▤ ";  I_5H="◷ ";  I_7D="▦ "  ;;
  *)       I_MODEL="";    I_CTX="";    I_5H="";    I_7D=""    ;;
esac

# --------------------------------------------------------------------- helpers

# A distinct hue per model family, so the model is identifiable at a glance.
# The status axis (red/yellow/green) is off limits — a model name must not read
# as a meter. Three hues remain, so mythos takes plain foreground, unknowns dim.
model_color() {
  case "$MODEL_ID" in
    *opus*)   REPLY=$MAGENTA ;;
    *fable*)  REPLY=$BBLUE   ;;
    *mythos*) REPLY=$RST     ;;
    *sonnet*) REPLY=$CYAN    ;;
    *haiku*)  REPLY=$BLUE    ;;
    *)        REPLY=$DIM     ;;
  esac
}

# Levels are low | medium | high | xhigh | max. Only "medium" is long enough to
# be worth shortening; anything unrecognised passes through as sent.
effort_label() {
  case "$1" in
    medium) REPLY=med ;;
    *)      REPLY=$1  ;;
  esac
}

# Percentages are floats, but the status line is too small to show decimals. 
# Round to the nearest integer, with 0.5 rounding up.
round_pct() {
  local p=${1:-0} int frac
  case $p in ''|*[!0-9.]*|*.*.*) REPLY=0; return ;; esac  # null, "abc", 1.2.3
  int=${p%%.*}; frac=${p#*.}
  # Nothing to strip in a dotless "5", so ${p#*.} hands back the 5 — which would
  # then read as the first decimal digit and round it up to 6.
  [ "$frac" = "$p" ] && frac=""
  case ${int:-0} in '') int=0 ;; esac                     # ".5" has no int part
  case ${frac:0:1} in [5-9]) int=$(( int + 1 )) ;; esac
  REPLY=$int
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

# Append a percent sign. Callers round with round_pct() first.
percentage_formatter() { REPLY="${1:-0}%"; }

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
add() { [ -n "$LINE" ] && LINE="$LINE$DIM$CCSL_SEP$RST"; LINE="$LINE$1"; }

# Effort is an attribute of the model, not a fourth meter, so it rides inside
# the model segment: parenthesised because that reads as a qualifier even at
# dim contrast, and dim because it must not compete with the model name.
# The field is absent for models without an effort parameter.
seg_model() {
  [ -n "$MODEL_NAME" ] || return 1
  local out
  model_color
  out="$I_MODEL$REPLY$MODEL_NAME$RST"
  if [ -n "$EFFORT" ] && [ "$CCSL_EFFORT" != never ]; then
    effort_label "$EFFORT"
    out="$out $DIM($REPLY)$RST"
  fi
  add "$out"
}

seg_context() {
  [ -n "$CTX_SIZE" ] && [ "${CTX_SIZE%%.*}" != 0 ] || return 1
  local used size pct c
  ctx_size_formatter "$CTX_USED"; used=$REPLY
  ctx_size_formatter "$CTX_SIZE"; size=$REPLY
  pct=$CTX_PCT
  if [ -z "$pct" ]; then pct=$(( CTX_USED * 100 / ${CTX_SIZE%%.*} )); fi
  round_pct "$pct"; pct=$REPLY
  local c
  percentage_color "$pct" "$CCSL_CRIT_CTX"; c=$REPLY
  percentage_formatter "$pct"
  add "$I_CTX$c$REPLY$RST $used/$size"
}

# Shared renderer for both rate-limit windows. Three visual levels: the label
# is static chrome so it dims, the percentage carries the status colour, and
# the countdown keeps the plain foreground — it is data, like the context
# segment's token counts.
seg_limit() {
  local icon=$1 label=$2 pct=$3 reset=$4 out c
  [ -n "$pct" ] || return 1
  round_pct "$pct"; pct=$REPLY
  percentage_color "$pct" "$CCSL_CRIT_LIMIT"; c=$REPLY
  percentage_formatter "$pct"
  out="$icon$DIM$label$RST $c$REPLY$RST"
  if [ -n "$reset" ]; then countdown "$reset"; out="$out $REPLY"; fi
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
