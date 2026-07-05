#!/usr/bin/env bash
set -euo pipefail

arg="${1:?usage: set-brightness.sh <0-100|+N|-N>}"

if [[ "$arg" =~ ^[+-][0-9]+$ ]]; then
    current=$(brightnessctl -d intel_backlight g)
    max=$(brightnessctl -d intel_backlight m)
    percent=$(awk -v cur="$current" -v max="$max" -v delta="$arg" 'BEGIN {
        raw_pct = cur / max * 100
        linear = (raw_pct/100)^(1/3) * 100
        new = linear + delta
        if (new < 0) new = 0
        if (new > 100) new = 100
        printf "%.0f", new
    }')
elif [[ "$arg" =~ ^[0-9]+$ ]] && (( arg <= 100 )); then
    percent="$arg"
else
    echo "brightness must be an integer 0-100, or +/-N for relative" >&2
    exit 1
fi

scaled=$(awk -v p="$percent" 'BEGIN {
    v = (p/100)^3 * 100
    if (v < 1 && p > 0) v = 1
    printf "%.0f", v
}')

echo $scaled
brightnessctl -d intel_backlight set "${scaled}%"
