#!/bin/bash
set -euo pipefail

source ./aur.sh
source ./internetconnection.sh
source ./pacman.sh
source ./setrandomwallpaper.sh

LOGFILE=${LOGFILE:-/tmp/startup.log}

log() {
    local msg
    msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
    echo "$msg" >>"$LOGFILE"
}

so() {
    local cmd=( "$@" )

    if [[ -n "${verbose:-}" ]]; then
        echo "+ ${cmd[*]}"
        "${cmd[@]}"
        return $?
    else
        local error
        # run the command, discard stdout, capture stderr in $error
        if ! error="$( { "${cmd[@]}" 1>/dev/null; } 2>&1 )"; then
            if [[ -z "$error" ]]; then
                error="Command failed: ${cmd[*]}"
            fi
            echo "${FUNCNAME[1]}: ${error}" >&2
            return 1
        fi
        return 0
    fi
}

rm -f $LOGFILE || true # prepare the log file for incoming bs

if random_wallpaper; then
    use_hyprpaper
else
    log "failed to setup a wallpaper."
fi

if pacmanupdate || pacmanrecovery ; then
    aur
else
    log "all updates have failed. no changes were made."
fi

