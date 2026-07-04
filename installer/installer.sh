#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ASSETS_DIR="$SCRIPT_DIR/assets"

MAINUSER="$(whoami)"
TEMPUSER="tempadmin_$(date +%s)"
AURHELPER="yay"
LOGFILE="$HOME/arch-setup.log"

# ---------------------------------------------------------------------------
# logging
# ---------------------------------------------------------------------------

log() {
    local msg
    msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
    echo "$msg" >>"$LOGFILE"
}

init() {
    clear
    : >"$LOGFILE"

    # no root allowed
    if [ "$EUID" -eq 0 ]; then
        echo "don't run this script as root."
        exit 1
    fi
    # arch x86_64
    if ! grep -q '^ID=arch$' /etc/os-release || [ "$(uname -m)" != "x86_64" ]; then
        echo "this script requires arch linux x86_64."
        exit 1
    fi
    # nvidia
    if ! lspci -nn | grep -E 'VGA|3D' | grep -iq 'nvidia'; then
        echo "this script requires nvidia's gpu, lspci check failed."
        exit 1
    fi

    internetconnection || { echo "no internet connection, aborting"; exit 1; }

    sudo -v || { echo "sudo authentication failed"; exit 1; }
    log "init checks passed"
}

tempuser() {
    log "creating temporary privileged user: $TEMPUSER"

    sudo useradd -m -s /bin/bash "$TEMPUSER"

    # Scoped to pacman only — this user's whole job is `makepkg`, which
    # internally shells out to `sudo pacman` to install build deps and the
    # finished package. It never needs anything beyond that.
    local tmp_sudoers
    tmp_sudoers=$(mktemp)
    echo "$TEMPUSER ALL=(ALL) NOPASSWD: /usr/bin/pacman*" >"$tmp_sudoers"
    if ! sudo visudo -cf "$tmp_sudoers"; then
        log "generated sudoers file failed validation, aborting"
        rm -f "$tmp_sudoers"
        sudo userdel -r "$TEMPUSER" || true
        exit 1
    fi
    sudo install -m 0440 -o root -g root "$tmp_sudoers" "/etc/sudoers.d/$TEMPUSER"
    rm -f "$tmp_sudoers"
}

cleanup() {
    log "purging temp user"

    if [[ -n "${KEEP_SUDO_PID:-}" ]]; then
        kill "$KEEP_SUDO_PID" 2>/dev/null || true
        wait "$KEEP_SUDO_PID" 2>/dev/null || true
    fi

    sudo rm -f "/etc/sudoers.d/$TEMPUSER"

    if id "$TEMPUSER" &>/dev/null; then
        sudo userdel -r "$TEMPUSER" || true
    fi

    if getent group "$TEMPUSER" >/dev/null; then
        sudo groupdel "$TEMPUSER" || true
    fi
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

internetconnection() {
    if ping -c 3 -W 10 -w 20 "8.8.8.8" || \
       ping -c 3 -W 10 -w 20 "1.1.1.1" || \
       ping -c 3 -W 10 -w 20 "8.8.4.4"; then
        log "internet connection established"
        return 0
    fi

    log "no internet connection"
    return 1
}

pacmanpkgs() {
    local failed=() pkgs=() src="$ASSETS_DIR/pacman.csv"

    [[ -f "$src" ]] || { log "missing $src"; exit 1; }

    for _ in 1 2 3; do sudo pacman -Syu --noconfirm && break; done || {
        log "pacman -Syu failed"
        exit 1
    }

    readarray -t pkgs < <(awk -F, 'NF && $1 !~ /^[[:space:]]*$/ {print $1}' "$src")
    log "${#pkgs[@]} packages listed, installing"

    if (( ${#pkgs[@]} == 0 )); then
        log "no packages listed in $src, skipping"
        return 0
    fi

    if ! sudo pacman -S --noconfirm --needed "${pkgs[@]}"; then
        log "something went wrong, attempting recovery"
        for pkg in "${pkgs[@]}"; do
            sudo pacman -S --noconfirm --needed "$pkg" || failed+=("$pkg")
        done
    fi

    if ((${#failed[@]})); then
        log "failed to install some packages: ${failed[*]}"
    else
        log "all packages have been installed"
    fi
}

installaurhelper() {
    sudo rm -rf "/tmp/$AURHELPER"
    log "installing chosen aur helper ($AURHELPER)"

    sudo -u "$TEMPUSER" git clone \
        "https://aur.archlinux.org/$AURHELPER.git" \
        "/tmp/$AURHELPER"

    cd "/tmp/$AURHELPER" || return 1
    sudo -u "$TEMPUSER" makepkg -sicrf --noconfirm
    cd "$SCRIPT_DIR" || return 1
}

aurpkgs() {
    local pkgs=() failed=() src="$ASSETS_DIR/aur.csv"

    command -v "$AURHELPER" >/dev/null || { log "$AURHELPER not found on PATH"; exit 1; }
    [[ -f "$src" ]] || { log "missing $src"; exit 1; }

    readarray -t pkgs < <(awk -F, 'NF && $1 !~ /^[[:space:]]*$/ {print $1}' "$src")
    log "${#pkgs[@]} aur packages listed, installing"

    for pkg in "${pkgs[@]}"; do
        sudo -u "$TEMPUSER" "$AURHELPER" -S --noconfirm --needed "$pkg" || failed+=("$pkg")
    done

    if ((${#failed[@]})); then
        log "failed to install some packages: ${failed[*]}"
    else
        log "all packages installed"
    fi
}

fonts() {
    # TODO: not yet implemented — fill in font packages / fc-cache steps here.
    log "fonts(): not yet implemented, skipping"
}

environment() {
    # autocpufreq
    #sudo systemctl enable auto-cpufreq.service
    # TLP, mask the conflicting service (CONFIGURE TO LEAVE THE CPU UP TO AUTOCPUFREQ)
    sudo systemctl enable tlp.service
    sudo systemctl mask systemd-rfkill.service
    sudo systemctl mask systemd-rfkill.socket
    # Enable weekly TRIM for SSDs/NVMEs to reduce write amplification and maintain performance
    sudo systemctl enable fstrim.timer
    # CUPS, minimal
    sudo systemctl enable cups.socket
    # ly display manager
    sudo systemctl disable getty@tty1.service
    sudo systemctl enable ly@tty1.service
    # disable bluetooth (unused)
    sudo systemctl disable bluetooth.service
    # avahi
    sudo systemctl disable avahi-daemon.service
    sudo systemctl enable avahi-daemon.socket

    # shell config, switch to fish
    if command -v fish >/dev/null 2>&1; then
        sudo chsh -s /bin/fish "$MAINUSER"
    else
        log "fish not installed, skipping chsh"
    fi

    # minor systemd-resolved tweaks
    local resolvedconf="/etc/systemd/resolved.conf"
    {
        echo "[Resolve]"
        echo "DNSOverTLS=yes"
        echo "Cache=yes"
    } | sudo tee "$resolvedconf" >/dev/null

    # enable zram [major performance boost]
    local zramdir="/etc/systemd"
    pacman -Qq zram-generator >/dev/null 2>&1 || sudo pacman -S --noconfirm --needed zram-generator
    sudo mkdir -p "$zramdir"
    {
        echo "[zram0]"
        echo "zram-size = ram / 2"
        echo "compression-algorithm = zstd"
    } | sudo tee "$zramdir/zram-generator.conf" >/dev/null
    sudo swapoff -a
    sudo systemctl enable systemd-zram-setup@zram0.service

    # sysctl tweaks, optimizing performance for high ram setups
    local sysctlconfig="/etc/sysctl.d/99-performance.conf"
    {
        echo "vm.swappiness=10"
        echo "vm.vfs_cache_pressure=50"
        echo "kernel.nmi_watchdog=0"
        echo "fs.inotify.max_user_watches=1048576"
    } | sudo tee "$sysctlconfig" >/dev/null

    # randomize mac address
    local nm_conf="/etc/NetworkManager/conf.d/random-mac.conf"
    sudo mkdir -p "$(dirname "$nm_conf")"
    {
        echo "[device]"
        echo "wifi.scan-rand-mac-address=yes"
        echo ""
        echo "[connection]"
        echo "wifi.cloned-mac-address=stable-random"
        echo "ethernet.cloned-mac-address=stable-random"
    } | sudo tee "$nm_conf" >/dev/null

    local makepkgconf="/etc/makepkg.conf"
    # use all available cores for compilation
    sudo sed -i "s/-j[0-9]\+/-j$(nproc)/;/^#MAKEFLAGS/s/^#//" "$makepkgconf"
    # use all available cores for compression
    sudo sed -i "s/^#COMPRESSZST=(zstd -c -z -q)/COMPRESSZST=(zstd -c -T$(nproc) -z -q)/" "$makepkgconf"
    # enable ccache for faster rebuilds
    sudo sed -i 's|#BUILDENV=.*!ccache.*|BUILDENV+=(ccache)|' "$makepkgconf"

    # colorful pacman, concurrent downloads, ILoveCandy, verbose lists, checkspace
    local pacmanconf="/etc/pacman.conf"
    sudo grep -q "ILoveCandy" "$pacmanconf" || sudo sed -i "/VerbosePkgLists/a ILoveCandy" "$pacmanconf"
    sudo sed -Ei \
        -e "s/^#?(ParallelDownloads).*/\1 = 15/" \
        -e "/^#?Color$/s/#//" \
        -e "s/^#VerbosePkgLists/VerbosePkgLists/" \
        -e "/ParallelDownloads/a CheckSpace" \
        "$pacmanconf"

    # sane defaults for grub, prepare for dual booting windows
    if [[ -f /etc/default/grub ]]; then
        sudo pacman -S --noconfirm --needed os-prober
        local conf="/etc/default/grub"
        sudo sed -i \
            -e 's/^#\?GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' \
            -e 's/^#\?GRUB_SAVEDEFAULT=.*/GRUB_SAVEDEFAULT=true/' \
            -e 's/^#\?GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=menu/' \
            -e 's/^#\?GRUB_DISABLE_SUBMENU=.*/GRUB_DISABLE_SUBMENU=y/' \
            -e 's/^#\?GRUB_DISABLE_RECOVERY=.*/GRUB_DISABLE_RECOVERY=true/' \
            -e 's/^#\?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' \
            -e 's/^#\?GRUB_DISABLE_LINUX_UUID=.*/GRUB_DISABLE_LINUX_UUID=false/' \
            -e 's/^#\?GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3"/' \
            "$conf"
        # NVMe-friendly module preload (faster boot device detection)
        if ! grep -q "^GRUB_PRELOAD_MODULES" "$conf"; then
            echo 'GRUB_PRELOAD_MODULES="part_gpt part_msdos"' | sudo tee -a "$conf" >/dev/null
        fi
        sudo grub-mkconfig -o /boot/grub/grub.cfg
    else
        log "GRUB not detected (/etc/default/grub missing), skipping bootloader config"
    fi

    # custom environment variables, readable but not writable/executable
    sudo mkdir -p "/etc/environment.d"
    if [[ -f "$ASSETS_DIR/ENV.txt" ]]; then
        sudo cp "$ASSETS_DIR/ENV.txt" "/etc/environment.d/10-custom.conf"
        sudo chmod 644 "/etc/environment.d/10-custom.conf"
    else
        log "missing $ASSETS_DIR/ENV.txt, skipping custom environment vars"
    fi
}

init

# refresh sudo every minute in the background so the long install doesn't
# hit a re-prompt; cleanup() kills this on any exit path, not just success
sudo -v
while true; do
    sleep 60
    sudo -v
done &
KEEP_SUDO_PID=$!

tempuser
pacmanpkgs
installaurhelper
aurpkgs
environment
fonts

log "all set, reboot now."
