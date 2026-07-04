#!/bin/bash
WALLPAPER=""

random_wallpaper() {
    local wallpaper_dir="wlp"
    local files=()
    local selected

    if [[ ! -d "$wallpaper_dir" ]]; then
        echo "error: Wallpaper directory not found: $wallpaper_dir" >&2
        return 1
    fi

    mapfile -d '' files < <(
        find "$wallpaper_dir" -maxdepth 1 -type f \
            \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
            -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.gif' \) \
            -print0
    )

    if (( ${#files[@]} == 0 )); then
        echo "Error: No image files found in $wallpaper_dir" >&2
        return 1
    fi

    selected="${files[RANDOM % ${#files[@]}]}"
    echo "selected wallpaper: $selected"
    WALLPAPER="$selected"
    return 0
}

use_hyprpaper() {
    nohup hyprpaper >/dev/null 2>&1 &
    disown

    hyprctl hyprpaper wallpaper ", ${WALLPAPER}, cover"
}



if random_wallpaper; then
    use_hyprpaper
fi
