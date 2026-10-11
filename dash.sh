#!/bin/sh

# ---------- config ----------
# BASE_URL lives in dash.env (not checked in) - see dash.env.example
ENV_FILE="${DASH_ENV:-$(dirname "$0")/dash.env}"
[ -f "$ENV_FILE" ] || { echo "missing $ENV_FILE" >&2; exit 1; }
. "$ENV_FILE"
QUERY="viewport=1448x1072&colors=000000%2C242424%2C494949%2C6D6D6D%2C929292%2CB6B6B6%2CDBDBDB%2CFFFFFF&lang=nl&rotate=90&zoom=1.76"
URL="${BASE_URL}?${QUERY}"

FBINK=fbink                       # full-path it if KFMon can't find it on PATH
RUN_DIR=/tmp/dash                 # script, dash.env and fbink run from here (RAM)
IMG="$RUN_DIR/dash.png"
TMP="$RUN_DIR/dash.png.new"
LOG_DIR=/mnt/onboard/.dash
LOG="$LOG_DIR/dash.log"           # kept on onboard ON PURPOSE: survives the crash so you can read it

INTERVAL_NORMAL=120               # seconds between refreshes (normal)
INTERVAL_MORNING=30               # seconds between refreshes in the morning window
MORNING_START=6                   # 06:00
MORNING_END=10                    # up to (not incl.) 10:00
DEGHOST_EVERY=10                  # do a full flashing refresh every Nth draw
MAX_LOG_LINES=2000                # trim the log so it can't grow forever
# ----------------------------

# run from RAM: copy ourselves, dash.env and fbink to $RUN_DIR and re-exec from
# there, so the loop keeps going while /mnt/onboard is unmounted (e.g. USB
# storage mode) instead of losing the files it runs from
if [ "$(cd "$(dirname "$0")" && pwd)" != "$RUN_DIR" ]; then
    mkdir -p "$RUN_DIR" &&
        cp -f "$0" "$RUN_DIR/dash.sh" &&
        cp -f "$ENV_FILE" "$RUN_DIR/dash.env" &&
        cp -f "$(command -v "$FBINK")" "$RUN_DIR/fbink" &&
        chmod +x "$RUN_DIR/fbink" ||
        { echo "failed to copy to $RUN_DIR" >&2; exit 1; }
    export DASH_ENV="$RUN_DIR/dash.env"
    cd / && exec sh "$RUN_DIR/dash.sh"
fi
FBINK="$RUN_DIR/fbink"

mkdir -p "$LOG_DIR"

drawcount=0
fails=0

# while onboard is unmounted the log can't be written; skip those lines quietly
log() {
    { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; } 2>/dev/null
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
    { tail -n "$MAX_LOG_LINES" "$LOG" > "$LOG.tmp" && mv -f "$LOG.tmp" "$LOG"; } 2>/dev/null
}

while true; do
    drawcount=$((drawcount + 1))

    # every Nth draw, do a flashing refresh to clear accumulated ghosting
    if [ "$((drawcount % DEGHOST_EVERY))" -eq 1 ]; then
        draw flash
    else
        draw
    fi

    trim_log

    # pick the interval for the next wait
    H=$(date +%H)
    H=${H#0}                        # strip leading zero to avoid octal (08/09)
    if [ "${H:-0}" -ge "$MORNING_START" ] && [ "${H:-0}" -lt "$MORNING_END" ]; then
        INTERVAL=$INTERVAL_MORNING
    else
        INTERVAL=$INTERVAL_NORMAL
    fi

    sleep "$INTERVAL"
done
