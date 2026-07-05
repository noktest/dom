#!/bin/bash
# sets timezone automatically (timedatectl)
source = ./internetconnection.sh

set -euo pipefail

APIS=(
  "https://ipapi.co/timezone/" # Europe/Warsaw
  "https://ipwho.is/?fields=timezone.id,timezone.time_zone" # {"timezone":{"id":"Europe/Warsaw"}}
  "https://free.freeipapi.com/api/json/" # {..., "timezone":{"id":"Europe/Warsaw"}, ...}
  "https://ip-api.com" # wall of text
)

# internet?
internetconnection > /dev/null || exit 1

for url in "${APIS[@]}"; do
   # extract the first thing that looks like iana timezone format, works with "\" too
   raw=$(curl -s --max-time 10 "$url") || continue
   timezone=$(echo "$raw" | grep -oE '[A-Z][a-z]+(\\?/([A-Z][a-z]+(_[A-Z][a-z]+)*))+' | sed 's#\\##g' | head -n1)
   # empty?
   [[ -n "$timezone" ]] || continue
   # real timezone?
   if timedatectl list-timezones | grep -Fq "$timezone"; then
       timedatectl set-timezone "$timezone" #set
       echo "$timezone"
       exit 0
   fi
done

echo "failed to set timezone"
exit 1
