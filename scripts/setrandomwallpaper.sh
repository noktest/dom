#!/bin/bash
set -euo pipefail

WALLPAPER=""

random_wallpaper() {
    local wallpaper_dir="wlp"
    local files=()
    local selected

    if [[ ! -d "$wallpaper_dir" ]]; then
        echo "directory not found: $wallpaper_dir" >&2
        return 1
    fi

    mapfile -d '' files < <(
        find "$wallpaper_dir" -maxdepth 1 -type f \
            \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
            -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.gif' \) \
            -print0
    )

    if (( ${#files[@]} == 0 )); then
        echo "no image files found in $wallpaper_dir" >&2
        return 1
    fi

    selected="${files[RANDOM % ${#files[@]}]}"
    echo "selected wallpaper: $selected"
    WALLPAPER="$selected"
    return 0
}

use_hyprpaper() {
    if ! pgrep -x hyprpaper >/dev/null; then
        nohup hyprpaper >/dev/null 2>&1 &
        disown
        sleep 0.2
    fi
    hyprctl hyprpaper wallpaper ", ${WALLPAPER}, cover"
}

use_awww() {
    if ! pgrep -x awww-daemon >/dev/null; then
        nohup awww-daemon >/dev/null 2>&1 &
        disown
        sleep 0.2
    fi
    awww img "${WALLPAPER}"
}


if random_wallpaper; then
    use_hyprpaper
fi
