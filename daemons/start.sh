#!/bin/bash
# System update daemon: pacman + AUR update, with recovery paths.
# Meant to run as a systemd service, as root, on each boot/launch.
set -euo pipefail

LOGFILE="${LOGFILE:-/var/log/system-update-daemon.log}"

# ---------------------------------------------------------------------------
# logging
# ---------------------------------------------------------------------------

log() {
    local msg
    msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
    echo "$msg" >>"$LOGFILE"
}

# ---------------------------------------------------------------------------
# guard: must run as root (systemd unit should run this as root)
# ---------------------------------------------------------------------------

if [[ ${EUID} -ne 0 ]]; then
    echo "this script must run as root (intended to run as a systemd service)" >&2
    exit 1
fi

touch "$LOGFILE" 2>/dev/null || {
    echo "cannot write to LOGFILE=$LOGFILE" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

internetconnection() {
    if ping -c 1 -W 2 "8.8.8.8" >/dev/null 2>&1 || \
       ping -c 1 -W 2 "1.1.1.1" >/dev/null 2>&1 || \
       ping -c 1 -W 2 "8.8.4.4" >/dev/null 2>&1; then
        log "internet connection established"
        return 0
    fi

    log "no internet connection"
    return 1
}

so() {
    local cmd=("$@")

    if [[ -n "${verbose:-}" ]]; then
        log "+ ${cmd[*]}"
        "${cmd[@]}"
        return $?
    else
        local error
        # run the command, discard stdout, capture stderr in $error
        if ! error="$( { "${cmd[@]}" 1>/dev/null; } 2>&1 )"; then
            if [[ -z "$error" ]]; then
                error="Command failed: ${cmd[*]}"
            fi
            log "${FUNCNAME[1]}: ${error}"
            return 1
        fi
        return 0
    fi
}

# ---------------------------------------------------------------------------
# pacman update + recovery
# ---------------------------------------------------------------------------

pacmanupdate() {
    local total updates percent

    for cmd in reflector paccache checkupdates; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log "missing dependency: $cmd"
            return 1
        fi
    done

    total=$(pacman -Qq 2>/dev/null | wc -l) || true
    updates=$(checkupdates 2>/dev/null | wc -l) || true
    : "${total:=0}"
    : "${updates:=0}"

    percent=0
    if (( total > 0 )); then
        (( percent = (updates * 100) / total )) || true
    fi

    if (( percent <= 10 && updates <= 20 )); then
        log "pending updates: $updates (${percent}%)"
        log "no need to update yet"
        return 0
    fi

    log "$total total packages on the system, $updates (${percent}%) will be updated"

    # attempt update
    if pacman -Syu --noconfirm; then
        # success, clean up
        local orphans=()
        mapfile -t orphans < <(pacman --query --deps --unrequired --quiet 2>/dev/null || true)
        if (( ${#orphans[@]} > 0 )); then
            so pacman --noconfirm --remove --recursive --unneeded "${orphans[@]}"
        fi

        # Remove uninstalled package cache first, keep only 2 latest versions of installed packages
        so paccache --remove --uninstalled --keep 0 || log "prune_cache: failed --uninstalled cleanup"
        so paccache --remove --keep 2 || log "prune_cache: failed trimming installed packages cache"

        log "pacmanupdate(): pacman packages updated"
        return 0
    else
        log "pacmanupdate(): pacman failed, attempting recovery"
        if pacmanrecovery; then
            return 0
        fi
        return 1
    fi
}

pacmanrecovery() {
    local reflectorflags=(
        --protocol https
        --latest 30
        --age 6
        --fastest 20
        --sort rate
        --connection-timeout 10
        --download-timeout 10
        --save "/etc/pacman.d/mirrorlist"
    )

    log "=== pacmanrecovery: recovery attempt started ==="

    # online?
    if ! internetconnection; then
        log "pacmanrecovery(): no internet connection."
        return 1
    fi

    # lock recovery
    if [[ -f /var/lib/pacman/db.lck ]]; then
        if pgrep -x pacman >/dev/null 2>&1; then
            log "pacmanrecovery(): can't remove pacman lock, pacman is active"
            return 1
        fi
        log "pacmanrecovery(): removing stale pacman lock"
        rm -f /var/lib/pacman/db.lck
    fi

    # key recovery
    if ! pacman-key --refresh-keys; then
        log "pacmanrecovery(): failed to refresh pacman keys."
    fi

    # mirror recovery
    if ! pacman -Syy --noconfirm; then
        log "pacmanrecovery(): package database sync failed, refreshing mirrorlist"
        reflector "${reflectorflags[@]}" || log "pacmanrecovery(): reflector failed, keeping existing mirrors"
    fi

    # database integrity check
    if ! pacman -Dk; then
        log "pacmanrecovery(): database is corrupted, possible missing dependencies."
        return 1
    fi

    # try again
    if pacman -Syu --noconfirm; then
        paccache -rk 3 -ruk0
        return 0
    fi

    log "pacmanrecovery(): pacman update failed after recovery attempt"
    return 1
}

# ---------------------------------------------------------------------------
# AUR update (runs the actual build as an unprivileged, disposable user)
# ---------------------------------------------------------------------------

aur() {
    local tmpuser sudoersfile helper
    local -a packages failed

    tmpuser="aurbuild-temporary-user"
    sudoersfile="/etc/sudoers.d/$tmpuser"

    # clean up any leftovers from a previous crashed run before we start
    if id "$tmpuser" >/dev/null 2>&1; then
        log "aur(): found leftover $tmpuser from a previous run, cleaning up first"
        pkill -KILL -u "$tmpuser" >/dev/null 2>&1 || true
        userdel -r "$tmpuser" >/dev/null 2>&1 || true
    fi
    rm -f "$sudoersfile"

    useradd -m "$tmpuser"
    passwd -d "$tmpuser"

    # write + validate the sudoers fragment before it's trusted
    local tmp_sudoers
    tmp_sudoers=$(mktemp)
    echo "$tmpuser ALL=(ALL) NOPASSWD: /usr/bin/pacman*" >"$tmp_sudoers"
    if ! visudo -cf "$tmp_sudoers"; then
        log "aur(): generated sudoers file failed validation, aborting"
        rm -f "$tmp_sudoers"
        userdel -r "$tmpuser" >/dev/null 2>&1 || true
        return 1
    fi
    install -m 0440 "$tmp_sudoers" "$sudoersfile"
    rm -f "$tmp_sudoers"

    # cleanup handlers
    cleanup() {
        pkill -TERM -u "$tmpuser" >/dev/null 2>&1 || true
        sleep 2
        pkill -KILL -u "$tmpuser" >/dev/null 2>&1 || true
        userdel -r "$tmpuser" >/dev/null 2>&1 || true
        rm -f "$sudoersfile"
    }

    on_signal() {
        local sig=$1
        cleanup
        trap - "$sig"
        kill -s "$sig" "$$"
    }

    trap cleanup EXIT
    for sig in SIGINT SIGTERM SIGHUP SIGQUIT SIGABRT SIGALRM; do
        # shellcheck disable=SC2064
        trap "on_signal $sig" "$sig"
    done

    # run a command as the temp user, safe quoting with "$@"
    runastmp() { runuser -u "$tmpuser" -- "$@"; }

    # determine the aur helper, default preference: paru, then yay
    helper=$(command -v paru || command -v yay) || true
    if [[ -z "${helper:-}" ]]; then
        log "aur(): this script requires yay or paru"
        return 1
    fi
    helper=${helper##*/}

    packages=()
    mapfile -t packages < <(runastmp "$helper" -Quq --aur 2>/dev/null || true)

    if [ ${#packages[@]} -eq 0 ]; then
        log "aur(): nothing to update"
        return 0
    fi

    log "aur(): using $helper, updating this many packages: ${#packages[@]}"

    aurupdate() {
        failed=()

        if runastmp "$helper" -Syu --aur --noconfirm; then
            log "aurupdate(): AUR update completed"
            return 0
        fi

        for pkg in "${packages[@]}"; do
            if runastmp "$helper" -S --noconfirm "${pkg}"; then
                log "aurupdate(): successfully installed ${pkg}"
            else
                log "aurupdate(): failed to install ${pkg}"
                [[ " ${failed[*]:-} " =~ " $pkg " ]] || failed+=("$pkg")
            fi
        done

        if [ ${#failed[@]} -ne 0 ]; then
            return 1
        fi
        return 0
    }

    aurrecovery() {
        if ! internetconnection; then
            log "aurrecovery(): no internet connection"
            return 1
        fi

        # some systems (e.g., firewalled networks) might block ICMP
        if ! ping -c 1 -W 2 aur.archlinux.org >/dev/null 2>&1 && \
           ! curl -s --head https://aur.archlinux.org >/dev/null 2>&1; then
            log "aurrecovery(): AUR is down"
            return 1
        fi

        if ! runastmp gpg --refresh-keys; then
            log "aurrecovery(): failed to refresh GPG keys"
            return 1
        fi

        if aurupdate; then
            log "aurrecovery(): AUR update completed after recovery"
            return 0
        fi

        log "aurrecovery(): AUR update failed after recovery"
        return 1
    }

    if aurupdate || aurrecovery; then
        log "aur(): all set."
        return 0
    fi

    if [ ${#failed[@]} -eq ${#packages[@]} ]; then
        log "aur(): all attempts to update AUR packages failed."
    else
        log "aur(): failed to update ${#failed[@]} out of ${#packages[@]} outdated packages: ${failed[*]}"
    fi
    return 1
}

# ---------------------------------------------------------------------------
# generic periodic-throttle helper (shared by any check that shouldn't run
# on literally every launch)
# ---------------------------------------------------------------------------

should_run_periodic() {
    # should_run_periodic <marker_file> <interval_seconds>
    local marker=$1 interval=$2 last=0 now
    if [[ -f "$marker" ]]; then
        last=$(stat -c %Y "$marker") || last=0
    fi
    now=$(date +%s)
    (( now - last >= interval ))
}

mark_ran() {
    mkdir -p "$(dirname "$1")"
    date +%s >"$1"
}

# ---------------------------------------------------------------------------
# .pacnew / .pacsave detection — cheap, run every launch
# ---------------------------------------------------------------------------

pacnew_check() {
    log "=== Checking for .pacnew/.pacsave files ==="
    local pacnews=()
    mapfile -t pacnews < <(find /etc -xdev \( -name '*.pacnew' -o -name '*.pacsave' \) 2>/dev/null || true)

    if (( ${#pacnews[@]} > 0 )); then
        log "pacnew_check(): found ${#pacnews[@]} pending config file(s) needing manual review:"
        local f
        for f in "${pacnews[@]}"; do
            log "  $f"
        done
    else
        log "pacnew_check(): no pending .pacnew/.pacsave files"
    fi
}

# ---------------------------------------------------------------------------
# failed systemd units — cheap, run every launch
# ---------------------------------------------------------------------------

failed_units_check() {
    log "=== Checking for failed systemd units ==="
    local failed_units=()
    mapfile -t failed_units < <(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' || true)

    if (( ${#failed_units[@]} > 0 )); then
        log "failed_units_check(): ${#failed_units[@]} failed unit(s): ${failed_units[*]}"
    else
        log "failed_units_check(): no failed units"
    fi
}

# ---------------------------------------------------------------------------
# SMART health — throttled to once/24h, since HDDs may need to spin up to
# answer and this doesn't meaningfully change launch-to-launch anyway
# ---------------------------------------------------------------------------

smart_health_check() {
    local marker="/var/lib/system-update-daemon/last_smart_check"
    local daily=$((24 * 3600))

    if ! command -v smartctl >/dev/null 2>&1; then
        log "smart_health_check(): smartctl not found, skipping (install smartmontools)"
        return 0
    fi

    if ! should_run_periodic "$marker" "$daily"; then
        log "smart_health_check(): skipping, already checked within the last 24h"
        return 0
    fi

    log "=== SMART health check ==="
    local dev found=0
    for dev in /dev/nvme[0-9]n[0-9] /dev/sd[a-z]; do
        [[ -e "$dev" ]] || continue
        found=1
        local health
        health=$(smartctl -H "$dev" 2>/dev/null | grep -E "SMART overall-health|SMART Health Status" || true)
        if [[ -n "$health" ]]; then
            log "  $dev: $health"
            if ! grep -qi "PASSED\|OK" <<<"$health"; then
                log "WARNING: $dev reports a failing SMART health status!"
            fi
        else
            log "  $dev: could not read SMART health"
        fi
    done

    if (( found == 0 )); then
        log "smart_health_check(): no /dev/sdX or /dev/nvmeXnY devices found"
    fi

    mark_ran "$marker"
}

# ---------------------------------------------------------------------------
# btrfs health check — defined but NOT invoked by default.
# Scrub/balance are non-trivial operations to trigger automatically on every
# boot; call `btrfshealth` explicitly (e.g. from a separate timer) once
# you've decided that's what you want.
# ---------------------------------------------------------------------------

btrfshealth() {
    local btrfs_root="/"
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')

    log "=== BTRFS Health Check: $now ==="

    log "Disk usage summary:"
    btrfs filesystem df "$btrfs_root" | tee -a "$LOGFILE"
    btrfs filesystem usage "$btrfs_root" | tee -a "$LOGFILE"

    log "Subvolumes:"
    btrfs subvolume list "$btrfs_root" | tee -a "$LOGFILE"

    # scrub (weekly)
    local scrub_marker="/var/lib/btrfs_last_scrub"
    local last_scrub=0
    if [[ -f "$scrub_marker" ]]; then
        last_scrub=$(stat -c %Y "$scrub_marker") || last_scrub=0
    fi

    local now_epoch weekly
    now_epoch=$(date +%s)
    weekly=$((7 * 24 * 3600))

    if (( now_epoch - last_scrub >= weekly )); then
        log "Starting weekly scrub..."
        if btrfs scrub start -B "$btrfs_root" | tee -a "$LOGFILE"; then
            printf '%s\n' "$now_epoch" >"$scrub_marker"
            log "Scrub completed successfully"
        else
            log "WARNING: Scrub failed!"
        fi
    else
        log "Skipping scrub; last run within 7 days"
    fi

    # balance (monthly)
    local balance_marker="/var/lib/btrfs_last_balance"
    local last_balance=0
    if [[ -f "$balance_marker" ]]; then
        last_balance=$(stat -c %Y "$balance_marker") || last_balance=0
    fi

    local monthly=$((30 * 24 * 3600))
    if (( now_epoch - last_balance >= monthly )); then
        log "Checking Btrfs balance..."
        if btrfs balance start -dusage=75 "$btrfs_root" | tee -a "$LOGFILE"; then
            printf '%s\n' "$now_epoch" >"$balance_marker"
            log "Balance completed successfully"
        else
            log "WARNING: Balance failed!"
        fi
    else
        log "Skipping balance; last run within 30 days"
    fi

    log "=== BTRFS Health Check Complete ==="
}

# ---------------------------------------------------------------------------
# entry point
# ---------------------------------------------------------------------------

if pacmanupdate; then
    aur
else
    log "system update failed even after recovery attempt; skipping AUR update"
fi

pacnew_check
failed_units_check
smart_health_check
