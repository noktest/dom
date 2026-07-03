#!/bin/bash
# Sets a random wallpaper for Hyprland, picking a backend based on power state:
#   - AC / charging / no-battery (desktop): swww (animated, higher resource)
#   - on battery, discharging:              hyprpaper (static, lower resource)
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
wallpaper_dir="${WALLPAPER_DIR:-$SCRIPT_DIR/wlp}"

LOGFILE="${WALLPAPER_LOGFILE:-${XDG_CACHE_HOME:-$HOME/.cache}/wallpaper.log}"
LOCKFILE="/run/user/${UID}/wallpaper.lock"

# ---------------------------------------------------------------------------
# logging
# ---------------------------------------------------------------------------

log() {
    local msg
    msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" >&2
    mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null || true
    echo "$msg" >>"$LOGFILE" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# single-instance lock — avoid racing daemon starts if triggered twice
# ---------------------------------------------------------------------------

mkdir -p "$(dirname "$LOCKFILE")" 2>/dev/null || true
exec 200>"$LOCKFILE"
if ! flock -n 200; then
    log "another instance is already running, exiting"
    exit 0
fi

# ---------------------------------------------------------------------------
# bail early if Hyprland isn't running — and tear down any wallpaper
# daemons that might still be lingering from a previous session
# ---------------------------------------------------------------------------

if ! pgrep -x Hyprland >/dev/null; then
    pgrep -x swww-daemon >/dev/null 2>&1 && pkill -x swww-daemon
    pgrep -x hyprpaper >/dev/null 2>&1 && pkill -x hyprpaper
    log "Hyprland is not running, nothing to do"
    exit 1
fi

# ---------------------------------------------------------------------------
# power state
# ---------------------------------------------------------------------------

# Returns 0 (true) if the system should be treated as "on AC":
#   - a Mains/USB power_supply reports online=1, OR
#   - a battery reports Charging/Full, OR
#   - no battery exists at all (desktop)
is_on_ac() {
    local supply type found_battery=0

    for supply in /sys/class/power_supply/*/; do
        [[ -d "$supply" ]] || continue
        type=$(<"${supply}type") 2>/dev/null || continue

        case "$type" in
            Mains|USB)
                if [[ -f "${supply}online" ]] && [[ "$(<"${supply}online")" == "1" ]]; then
                    return 0
                fi
                ;;
            Battery)
                found_battery=1
                if [[ -f "${supply}status" ]]; then
                    local status
                    status=$(<"${supply}status")
                    [[ "$status" == "Charging" || "$status" == "Full" ]] && return 0
                fi
                ;;
        esac
    done

    (( found_battery == 0 )) && return 0   # desktop, no battery: treat as AC
    return 1
}

# ---------------------------------------------------------------------------
# wallpaper file selection
# ---------------------------------------------------------------------------

if [[ ! -d "$wallpaper_dir" ]]; then
    log "wallpaper directory not found: $wallpaper_dir"
    exit 1
fi

mapfile -t files < <(
    find "$wallpaper_dir" -maxdepth 1 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
           -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.gif' \) \
        -print 2>/dev/null
)

if (( ${#files[@]} == 0 )); then
    log "no image files found in $wallpaper_dir"
    exit 1
fi

selected="${files[RANDOM % ${#files[@]}]}"
log "selected wallpaper: $selected"

# ---------------------------------------------------------------------------
# backend: swww (animated, AC)
# ---------------------------------------------------------------------------

wait_for() {
    # wait_for <check-command...> — polls until it succeeds or times out
    local i=0
    until "$@" >/dev/null 2>&1; do
        (( i++ >= 25 )) && return 1
        sleep 0.2
    done
    return 0
}

use_swww() {
    local img=$1

    if ! command -v swww >/dev/null 2>&1; then
        log "swww not installed"
        return 1
    fi

    pgrep -x hyprpaper >/dev/null 2>&1 && pkill -x hyprpaper

    if ! pgrep -x swww-daemon >/dev/null 2>&1; then
        nohup swww-daemon >/dev/null 2>&1 &
        disown
        if ! wait_for swww query; then
            log "swww-daemon did not become ready in time"
            return 1
        fi
    fi

    swww img "$img" --transition-type grow --transition-fps 60
}

# ---------------------------------------------------------------------------
# backend: hyprpaper (static, battery)
# ---------------------------------------------------------------------------

use_hyprpaper() {
    local img=$1

    if ! command -v hyprpaper >/dev/null 2>&1; then
        log "hyprpaper not installed"
        return 1
    fi

    pgrep -x swww-daemon >/dev/null 2>&1 && pkill -x swww-daemon

    if ! pgrep -x hyprpaper >/dev/null 2>&1; then
        nohup hyprpaper >/dev/null 2>&1 &
        disown
        if ! wait_for hyprctl hyprpaper listloaded; then
            log "hyprpaper did not become ready in time"
            return 1
        fi
    fi

    hyprctl hyprpaper preload "$img" >/dev/null
    hyprctl hyprpaper wallpaper ",$img" >/dev/null
    hyprctl hyprpaper unload unused >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# choose backend based on power state, with a fallback if the preferred
# backend isn't installed
# ---------------------------------------------------------------------------

if is_on_ac; then
    log "power state: AC — preferring swww"
    if use_swww "$selected"; then
        exit 0
    fi
    log "falling back to hyprpaper"
    use_hyprpaper "$selected" && exit 0
else
    log "power state: battery — preferring hyprpaper"
    if use_hyprpaper "$selected"; then
        exit 0
    fi
    log "falling back to swww"
    use_swww "$selected" && exit 0
fi

log "failed to set wallpaper with any available backend"
exit 1
