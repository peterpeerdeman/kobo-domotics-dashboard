#!/bin/sh

# ---------- config ----------
# BASE_URL lives in dash.env (not checked in) - see dash.env.example
ENV_FILE="${DASH_ENV:-$(dirname "$0")/dash.env}"
[ -f "$ENV_FILE" ] || { echo "missing $ENV_FILE" >&2; exit 1; }
. "$ENV_FILE"
QUERY="viewport=1448x1072&colors=000000%2C242424%2C494949%2C6D6D6D%2C929292%2CB6B6B6%2CDBDBDB%2CFFFFFF&lang=en&rotate=90&zoom=1.76"
URL="${BASE_URL}?${QUERY}"

FBINK=fbink                       # full-path it if KFMon can't find it on PATH
IMG=/tmp/dash.png
TMP=/tmp/dash.png.new
CTRL=/mnt/onboard/.dash           # drop control files here
LOG="$CTRL/dash.log"              # kept on onboard ON PURPOSE: survives the crash so you can read it

INTERVAL_NORMAL=120               # seconds between refreshes (normal)
INTERVAL_MORNING=30               # seconds between refreshes in the morning window
MORNING_START=6                   # 06:00
MORNING_END=10                    # up to (not incl.) 10:00
DEGHOST_EVERY=10                  # do a full flashing refresh every Nth draw
MAX_LOG_LINES=2000                # trim the log so it can't grow forever
TICK=5                            # how often to check control files, seconds
# ----------------------------

mkdir -p "$CTRL"

drawcount=0
fails=0
force_flash=0

# read battery % and charge status (Charging/Discharging/Full) - the 06:45 diagnostic
read_batt() {
    cap=$(cat /sys/class/power_supply/*/capacity 2>/dev/null | head -n1)
    st=$(cat /sys/class/power_supply/*/status 2>/dev/null | head -n1)
    printf '%s%% %s' "${cap:-?}" "${st:-?}"
}

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$(read_batt)] $*" >> "$LOG"
    sync                          # flush now, so the last lines survive a hard power cut
}

log "=== dash.sh started ==="

# take over the screen (kill UI + the watchdog that respawns it)
killall -q -TERM nickel hindenburg sickel fickel 2>/dev/null

# guarantee an SSH way back in - dropbear survives nickel being gone.
pidof dropbear >/dev/null 2>&1 || dropbear -R >/dev/null 2>&1 &

# draw [flash]
#   no arg  -> fast, no-flash update (no flicker, but ghosts over time)
#   "flash" -> full flashing refresh (brief flash, clears ghosting)
draw() {
    # fetch to a temp file so a failure never clobbers the last good image
    if wget -q -T 30 -t 2 -O "$TMP" "$URL" && [ -s "$TMP" ]; then
        mv -f "$TMP" "$IMG"
        if [ "$1" = "flash" ]; then
            "$FBINK" -q -f -g file="$IMG"
        else
            "$FBINK" -q -g file="$IMG"
        fi
        log "ok${1:+ (flash)}"
        fails=0
    else
        rm -f "$TMP"
        fails=$((fails + 1))
        log "FETCH FAILED (consecutive: $fails)"
        # after a few misses, flash the stale image so it's obvious it's stale
        if [ "$fails" -eq 3 ] && [ -s "$IMG" ]; then
            "$FBINK" -q -f -g file="$IMG"
        fi
    fi
}

trim_log() {
    lines=$(wc -l < "$LOG" 2>/dev/null) || return
    [ "${lines:-0}" -le "$MAX_LOG_LINES" ] && return
    tail -n "$MAX_LOG_LINES" "$LOG" > "$LOG.tmp" && mv -f "$LOG.tmp" "$LOG"
}

while true; do
    drawcount=$((drawcount + 1))

    # flash on a manual refresh, or every Nth draw to clear accumulated ghosting
    if [ "$force_flash" -eq 1 ] || [ "$((drawcount % DEGHOST_EVERY))" -eq 1 ]; then
        draw flash
    else
        draw
    fi
    force_flash=0

    trim_log

    # pick the interval for the next wait
    H=$(date +%H)
    H=${H#0}                        # strip leading zero to avoid octal (08/09)
    if [ "${H:-0}" -ge "$MORNING_START" ] && [ "${H:-0}" -lt "$MORNING_END" ]; then
        INTERVAL=$INTERVAL_MORNING
    else
        INTERVAL=$INTERVAL_NORMAL
    fi

    # wait out the interval in small ticks so control files act within ~TICK seconds
    waited=0
    while [ "$waited" -lt "$INTERVAL" ]; do
        if [ -f "$CTRL/reboot" ]; then
            rm -f "$CTRL/reboot"
            log "reboot requested via control file"
            sync
            reboot
        fi
        if [ -f "$CTRL/refresh" ]; then
            rm -f "$CTRL/refresh"
            log "manual refresh requested"
            force_flash=1
            break
        fi
        sleep "$TICK"
        waited=$((waited + TICK))
    done
done
