#!/bin/bash
#
# Docker vDisk Usage Analyzer for Unraid
# Reports vDisk size, location, and per-container/image/volume space usage.
#
# Version:  1.0
# Date:     March 3, 2026
# Author:   Chris Neal
# Repo:     https://github.com/mrchrisneal/misc-scripts
# Path:     unraid/docker_vdisk_usage/docker_vdisk_usage.sh
#

SEP="================================================================"

# --- Locate the Docker vDisk ---
DOCKER_CFG="/boot/config/docker.cfg"
if [[ -f "$DOCKER_CFG" ]]; then
    VDISK_PATH=$(grep -i '^DOCKER_IMAGE_FILE=' "$DOCKER_CFG" | cut -d'=' -f2 | tr -d '"')
fi

if [[ -z "$VDISK_PATH" || ! -f "$VDISK_PATH" ]]; then
    echo "Could not locate Docker vDisk from config. Attempting fallback..."
    VDISK_PATH=$(losetup -a 2>/dev/null | grep -i 'docker' | head -1 | sed 's/.*(\(.*\))/\1/')
fi

if [[ -z "$VDISK_PATH" || ! -f "$VDISK_PATH" ]]; then
    echo "Error: Unable to locate the Docker vDisk image." >&2
    exit 1
fi

# --- Locate the mount point ---
LOOP_DEV=$(losetup -a 2>/dev/null | grep "$VDISK_PATH" | cut -d: -f1)
if [[ -n "$LOOP_DEV" ]]; then
    MOUNT_POINT=$(findmnt -n -o TARGET "$LOOP_DEV" 2>/dev/null | head -1)
fi

if [[ -z "$MOUNT_POINT" ]]; then
    MOUNT_POINT="/var/lib/docker"
fi

# --- Gather vDisk info ---
VDISK_SIZE_BYTES=$(stat -c%s "$VDISK_PATH" 2>/dev/null)
VDISK_SIZE=$(numfmt --to=iec-i --suffix=B "$VDISK_SIZE_BYTES" 2>/dev/null || ls -lh "$VDISK_PATH" | awk '{print $5}')

DF_LINE=$(df -h "$MOUNT_POINT" 2>/dev/null | tail -1)
USED=$(echo "$DF_LINE" | awk '{print $3}')
AVAIL=$(echo "$DF_LINE" | awk '{print $4}')
USE_PCT=$(echo "$DF_LINE" | awk '{print $5}')

# --- Helper: generate N nbsp characters ---
nbsps() {
    local count=$1
    local out=""
    for (( i=0; i<count; i++ )); do
        out="${out}&nbsp;"
    done
    echo -n "$out"
}

# --- Helper: right-pad text to width using nbsp ---
npad() {
    local text="$1"
    local width="$2"
    local len=${#text}
    local gap=$(( width - len ))
    [[ $gap -lt 1 ]] && gap=1
    echo -n "${text}$(nbsps $gap)"
}

# --- Helper: enforce 1 decimal place on values under 100 ---
# e.g. "4.59MB" -> "4.6MB", "67.7MB" stays, "917MB" stays, "0B" stays
fmt_size() {
    # 1) Truncate 2+ decimal places to 1: "4.59MB" -> "4.5MB"
    # 2) Add .0 to whole numbers under 100: "67MB" -> "67.0MB"
    echo "$1" | sed -E \
        -e 's/([0-9]{1,2})\.([0-9])[0-9]+([kKMGT]?B)/\1.\2\3/g' \
        -e 's/([^0-9.])([0-9]{1,2})([kKMGT]B)/\1\2.0\3/g' \
        -e 's/^([0-9]{1,2})([kKMGT]B)/\1.0\2/g'
}

# --- Print header ---
echo ""
echo "$SEP"
echo "$(nbsps 2)DOCKER vDISK USAGE REPORT"
echo "$SEP"
echo ""
echo "$(nbsps 2)vDisk Image$(nbsps 2):$(nbsps 2)$VDISK_PATH"
echo "$(nbsps 2)Mounted At$(nbsps 3):$(nbsps 2)$MOUNT_POINT"
echo "$(nbsps 2)vDisk Size$(nbsps 3):$(nbsps 2)$VDISK_SIZE"
echo "$(nbsps 2)Used / Free$(nbsps 2):$(nbsps 2)$USED used$(nbsps 2)|$(nbsps 2)$AVAIL free$(nbsps 2)|$(nbsps 2)$USE_PCT utilized"
echo ""

# --- Docker system overview (formatted with nbsp) ---
echo "$SEP"
echo "$(nbsps 2)SYSTEM OVERVIEW"
echo "$SEP"
echo ""

# Define column widths for system overview
SO_C1=18  # TYPE
SO_C2=8   # TOTAL
SO_C3=8   # ACTIVE
SO_C4=10  # SIZE
SO_C5=20  # RECLAIMABLE

docker system df 2>/dev/null | while IFS= read -r line; do
    # Parse each field from the line
    if echo "$line" | grep -q '^TYPE'; then
        echo "$(nbsps 2)$(npad "TYPE" $SO_C1)$(npad "TOTAL" $SO_C2)$(npad "ACTIVE" $SO_C3)$(npad "SIZE" $SO_C4)RECLAIMABLE"
    else
        # Fields: type, total, active, size, reclaimable (may have spaces like "2.658GB (4%)")
        type=$(echo "$line" | awk '{print $1" "$2}')
        # Handle "Build Cache" vs "Images" etc
        if echo "$line" | grep -q "^Build Cache"; then
            type="Build Cache"
            total=$(echo "$line" | awk '{print $3}')
            active=$(echo "$line" | awk '{print $4}')
            size=$(echo "$line" | awk '{print $5}')
            reclaim=$(echo "$line" | awk '{for(i=6;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')
        elif echo "$line" | grep -q "^Local Volumes"; then
            type="Local Volumes"
            total=$(echo "$line" | awk '{print $3}')
            active=$(echo "$line" | awk '{print $4}')
            size=$(echo "$line" | awk '{print $5}')
            reclaim=$(echo "$line" | awk '{for(i=6;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')
        else
            type=$(echo "$line" | awk '{print $1}')
            total=$(echo "$line" | awk '{print $2}')
            active=$(echo "$line" | awk '{print $3}')
            size=$(echo "$line" | awk '{print $4}')
            reclaim=$(echo "$line" | awk '{for(i=5;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')
        fi
        [[ -z "$type" || -z "$total" ]] && continue
        echo "$(nbsps 2)$(npad "$type" $SO_C1)$(npad "$total" $SO_C2)$(npad "$active" $SO_C3)$(npad "$size" $SO_C4)$reclaim"
    fi
done
echo ""

# =====================================================================
# CONTAINERS
# =====================================================================
echo "$SEP"
echo "$(nbsps 2)Scanning containers... this may take a minute."
echo "$SEP"
echo ""

CTMP=$(mktemp)

docker ps -a --format '{{.Names}}|{{.State}}|{{.Size}}' 2>/dev/null | while IFS='|' read -r name state size; do
    raw=$(echo "$size" | awk '{print $1}')
    echo "${name}|${state}|${size}|${raw}"
done > "$CTMP"

CMAX=$(awk -F'|' '{ if (length($1) > m) m=length($1) } END { print m+2 }' "$CTMP")
[[ "$CMAX" -lt 12 ]] && CMAX=12
SMAX=12

echo "$(nbsps 2)$(npad "CONTAINER" $CMAX)$(npad "STATUS" $SMAX)SIZE"
echo ""

sort -t'|' -k4 -h -r "$CTMP" | while IFS='|' read -r name state size raw; do
    size=$(fmt_size "$size")
    echo "$(nbsps 2)$(npad "$name" $CMAX)$(npad "$state" $SMAX)$size"
done
rm -f "$CTMP"
echo ""

# =====================================================================
# IMAGES — exclude dangling <none>:<none>
# =====================================================================
echo "$SEP"
echo "$(nbsps 2)IMAGES"
echo "$SEP"
echo ""

ITMP=$(mktemp)
docker images --format '{{.Repository}}|{{.Tag}}|{{.Size}}' 2>/dev/null | while IFS='|' read -r repo tag size; do
    [[ "$repo" == "<none>" ]] && continue
    echo "${repo}:${tag}|${size}"
done > "$ITMP"

IMAX=$(awk -F'|' '{ if (length($1) > m) m=length($1) } END { print m+2 }' "$ITMP")
[[ "$IMAX" -lt 16 ]] && IMAX=16

echo "$(nbsps 2)$(npad "REPOSITORY:TAG" $IMAX)SIZE"
echo ""

sort -t'|' -k2 -h -r "$ITMP" | while IFS='|' read -r repo size; do
    size=$(fmt_size "$size")
    echo "$(nbsps 2)$(npad "$repo" $IMAX)$size"
done
rm -f "$ITMP"
echo ""

# =====================================================================
# VOLUMES — map to container names, sorted by size desc, hide 0B
# =====================================================================
echo "$SEP"
echo "$(nbsps 2)Scanning volumes... this may take a few minutes."
echo "$SEP"
echo ""

declare -A VOL_OWNERS
for cid in $(docker ps -a -q 2>/dev/null); do
    cname=$(docker inspect --format '{{.Name}}' "$cid" 2>/dev/null | sed 's|^/||')
    mounts=$(docker inspect --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{"\n"}}{{end}}{{end}}' "$cid" 2>/dev/null)
    while IFS= read -r volname; do
        [[ -z "$volname" ]] && continue
        if [[ -n "${VOL_OWNERS[$volname]}" ]]; then
            VOL_OWNERS["$volname"]="${VOL_OWNERS[$volname]}, ${cname}"
        else
            VOL_OWNERS["$volname"]="$cname"
        fi
    done <<< "$mounts"
done

VTMP=$(mktemp)
ZERO_ORPHANS=0
ZERO_NAMED=0

for vol in $(docker volume ls -q 2>/dev/null); do
    mountpoint=$(docker volume inspect "$vol" --format '{{.Mountpoint}}' 2>/dev/null)
    if [[ -d "$mountpoint" ]]; then
        size_bytes=$(du -sb "$mountpoint" 2>/dev/null | awk '{print $1}')
        size_h=$(du -sh "$mountpoint" 2>/dev/null | awk '{print $1}')
    else
        size_bytes=0
        size_h="0"
    fi

    if [[ ${#vol} -eq 64 ]] && [[ "$vol" =~ ^[a-f0-9]+$ ]]; then
        owners="${VOL_OWNERS[$vol]}"
        if [[ -n "$owners" ]]; then
            display_name="${owners} (anon)"
        else
            display_name="${vol:0:12}... (orphan)"
        fi
        if [[ "$size_bytes" -eq 0 ]] && [[ -z "$owners" ]]; then
            ZERO_ORPHANS=$(( ZERO_ORPHANS + 1 ))
            continue
        fi
    else
        owners="${VOL_OWNERS[$vol]}"
        if [[ -n "$owners" ]]; then
            display_name="${vol} [${owners}]"
        else
            display_name="$vol"
        fi
        if [[ "$size_bytes" -eq 0 ]]; then
            ZERO_NAMED=$(( ZERO_NAMED + 1 ))
            continue
        fi
    fi

    echo "${size_bytes}|${display_name}|${size_h}" >> "$VTMP"
done

VMAX=$(awk -F'|' '{ if (length($2) > m) m=length($2) } END { print m+2 }' "$VTMP" 2>/dev/null)
[[ -z "$VMAX" || "$VMAX" -lt 12 ]] && VMAX=12

echo "$(nbsps 2)$(npad "VOLUME" $VMAX)SIZE"
echo ""

sort -t'|' -k1 -n -r "$VTMP" | while IFS='|' read -r raw_bytes display size_h; do
    echo "$(nbsps 2)$(npad "$display" $VMAX)$size_h"
done
rm -f "$VTMP"

echo ""
if [[ "$ZERO_ORPHANS" -gt 0 || "$ZERO_NAMED" -gt 0 ]]; then
    echo "$(nbsps 2)(${ZERO_ORPHANS} empty orphan volumes and ${ZERO_NAMED} empty named volumes hidden)"
    echo ""
fi

echo "$SEP"

ORPHAN_COUNT=$(docker volume ls -f dangling=true -q 2>/dev/null | wc -l)
if [[ "$ORPHAN_COUNT" -gt 0 ]]; then
    echo ""
    echo "$(nbsps 2)TIP: ${ORPHAN_COUNT} orphan volumes detected."
    echo "$(nbsps 2)Preview cleanup:$(nbsps 2)docker volume ls -f dangling=true"
    echo "$(nbsps 2)Remove all:$(nbsps 7)docker volume prune"
    echo ""
    echo "$SEP"
fi

DANGLING_IMAGES=$(docker images -f dangling=true -q 2>/dev/null | wc -l)
if [[ "$DANGLING_IMAGES" -gt 0 ]]; then
    echo ""
    echo "$(nbsps 2)TIP: ${DANGLING_IMAGES} dangling (untagged) images detected."
    echo "$(nbsps 2)Remove all:$(nbsps 2)docker image prune"
    echo ""
    echo "$SEP"
fi

echo ""
echo "$(nbsps 2)Report generated: $(date '+%Y-%m-%d %H:%M:%S')"
echo "$SEP"
echo ""
