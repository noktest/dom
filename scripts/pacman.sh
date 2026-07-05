#!/bin/bash



pacmanupdate() {
  local total updates percent

  for cmd in reflector paccache checkupdates; do
      if ! command -v "$cmd" >/dev/null 2>&1; then
          echo "missing dependency: $cmd" >&2
          return 1
      fi
  done

  total=$(pacman -Qq 2>/dev/null | wc -l)
  updates=$(checkupdates 2>/dev/null | wc -l)

  (( percent = total > 0 ? (updates * 100) / total : 0 ))

  if (( percent <= 10 )); then
    echo "pending updates: $updates (${percent}%)"
    echo "no need to update yet"
    return 0
  fi

  echo "$total total packages on the system, $updates (${percent}%) will be updated"

  # attempt update
  if sudo pacman -Syu --noconfirm; then
    # orphans
    local orphans
    orphans="$(pacman --query --deps --unrequired --quiet || true)"
    if [[ -n "${orphans}" ]]; then
        so pacman --noconfirm --remove --recursive --unneeded ${orphans}
    fi
    # cache
    if ! command -v paccache >/dev/null 2>&1; then
        echo "pacmanupdate(): paccache not found; skipping cache pruning"
        return 0
    fi
    # Remove uninstalled package cache first, Keep only 2 latest versions of installed packages
    so sudo paccache --remove --uninstalled --keep 0 || echo "pacmanupdate(): failed --uninstalled cleanup"
    so sudo paccache --remove --keep 2 || echo "pacmanupdate(): failed trimming installed packages cache"

    echo "pacmanupdate(): pacman packages updated"
    return 0
  else
    echo "pacmanupdate(): pacman failed, attempting recovery"
    pacmanrecovery || return 1
    return 0
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

  # online?
  if ! internetconnection; then
    echo "aurrecovery(): no internet connection."
    return 1
  fi

  # lock recovery
  if [[ -f /var/lib/pacman/db.lck ]]; then
    if pgrep -x pacman; then
      echo "aurrecovery(): can't remove pacman lock, pacman is active"
      return 1
    fi
    echo "aurrecovery(): removing stale pacman lock"
    sudo rm -f /var/lib/pacman/db.lck
  fi

  # key recovery
  if ! sudo pacman-key --refresh-keys; then
    echo "aurrecovery(): failed to refresh pacman keys."
  fi

  # mirror recovery
  if ! sudo pacman -Syy --noconfirm; then
    echo "aurrecovery(): package database sync failed, refreshing mirrorlist"
    sudo reflector "${reflectorflags[@]}" ||\
      echo "aurrecovery(): reflector failed, keeping existing mirrors"
  fi

  # database integrity check
  if ! sudo pacman -Dk; then
    echo "aurrecovery(): database is corrupted, possible missing depndencies."
    return 1
  fi

  # try again
  if sudo pacman -Syu --noconfirm; then
    # success, clean up
    sudo paccache -rk 3 -ruk0
    return 0
  fi

  echo "aurrecovery(): pacman update failed after recovery attempt"
  return 1
}
