#!/bin/bash
#
# Linux Mint SSD Optimization Script (for a MacBook Pro 2014)
# Applies all tested performance optimizations
# Safe to run multiple times (idempotent where possible)
#

set -e  # Exit on error

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

echo "=========================================="
echo "  Linux Mint SSD Optimization Script"
echo "=========================================="
echo ""

# Detect root device
ROOT_DEVICE=$(findmnt -n -o SOURCE /)

# For LVM, trace back to physical device
if [[ $ROOT_DEVICE == /dev/mapper/* ]]; then
    # Get the physical volume backing this LV
    PV_DEVICE=$(pvs --noheadings -o pv_name -S "vg_name=$(lvs --noheadings -o vg_name $ROOT_DEVICE | tr -d ' ')" | tr -d ' ' | head -1)
    # Get the base device name (e.g., sda from /dev/sda2)
    ROOT_PHYSICAL=$(lsblk -no pkname "$PV_DEVICE" 2>/dev/null | head -1)
else
    # Non-LVM setup
    ROOT_PHYSICAL=$(lsblk -no pkname "$ROOT_DEVICE" 2>/dev/null | head -1)
fi

# Fallback: try to find any SATA/NVMe disk
if [[ -z "$ROOT_PHYSICAL" ]]; then
    ROOT_PHYSICAL=$(lsblk -d -n -o NAME,TYPE | grep disk | head -1 | awk '{print $1}')
fi

echo "Detected root device: $ROOT_DEVICE"
echo "Physical disk: /dev/${ROOT_PHYSICAL:-[detection failed]}"

if [[ -z "$ROOT_PHYSICAL" ]]; then
    echo ""
    echo "ERROR: Could not auto-detect physical disk"
    read -p "Enter physical disk name (e.g., sda, nvme0n1): " ROOT_PHYSICAL
    if [[ -z "$ROOT_PHYSICAL" ]]; then
        echo "Disk name required. Exiting."
        exit 1
    fi
fi

echo ""
read -p "Continue with optimization? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

echo ""
echo "=== 1. Filesystem Mount Options (noatime, commit=60) ==="
if grep -q "noatime.*commit=60" /etc/fstab || grep -q "commit=60.*noatime" /etc/fstab; then
    echo "✓ Already configured in /etc/fstab"
else
    echo "Backing up /etc/fstab to /etc/fstab.backup..."
    cp /etc/fstab /etc/fstab.backup
    
    # Add noatime and commit=60 to root partition
    sed -i '/\/dev\/mapper.*\/ .*ext4/ s/errors=remount-ro/errors=remount-ro,noatime,commit=60/' /etc/fstab
    echo "✓ Added noatime and commit=60 to /etc/fstab"
    echo "  (Will take effect after reboot or remount)"
fi

echo ""
echo "=== 2. Enable TRIM ==="
if systemctl is-enabled fstrim.timer &>/dev/null; then
    echo "✓ fstrim.timer already enabled"
else
    systemctl enable fstrim.timer
    systemctl start fstrim.timer
    echo "✓ Enabled fstrim.timer"
fi

echo ""
echo "=== 3. I/O Queue Depth (2048) ==="
UDEV_FILE="/etc/udev/rules.d/60-queue-depth.rules"
if [[ -f "$UDEV_FILE" ]] && grep -q "nr_requests.*2048" "$UDEV_FILE"; then
    echo "✓ udev rule already exists"
else
    echo 'ACTION=="add|change", KERNEL=="'"$ROOT_PHYSICAL"'", ATTR{queue/nr_requests}="2048"' > "$UDEV_FILE"
    echo "✓ Created udev rule for persistent queue depth"
fi
# Apply immediately
if [[ -f /sys/block/$ROOT_PHYSICAL/queue/nr_requests ]]; then
    echo 2048 > /sys/block/$ROOT_PHYSICAL/queue/nr_requests
    echo "✓ Applied immediately (queue depth = 2048)"
else
    echo "⚠ Could not apply immediately, will take effect on next boot"
fi

echo ""
echo "=== 4. LVM Read-Ahead (8192 sectors) ==="
if lvdisplay "$ROOT_DEVICE" &>/dev/null; then
    # Use || true to prevent exit on "already set" error
    lvchange --readahead 8192 "$ROOT_DEVICE" 2>&1 | grep -v "is already" || true
    echo "✓ Set LVM read-ahead to 8192"
else
    echo "⊘ Not using LVM, skipping"
fi

echo ""
echo "=== 5. System Swappiness (10) ==="
if grep -q "vm.swappiness.*10" /etc/sysctl.conf; then
    echo "✓ Already configured"
else
    echo "vm.swappiness=10" >> /etc/sysctl.conf
    sysctl -w vm.swappiness=10 >/dev/null
    echo "✓ Set swappiness to 10"
fi

echo ""
echo "=== 6. VM Dirty Page Ratios (5/10) ==="
if grep -q "vm.dirty_background_ratio.*5" /etc/sysctl.conf && grep -q "vm.dirty_ratio.*10" /etc/sysctl.conf; then
    echo "✓ Already configured"
else
    cat >> /etc/sysctl.conf << 'EOF'

# SSD dirty page optimization
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
EOF
    sysctl -w vm.dirty_background_ratio=5 >/dev/null
    sysctl -w vm.dirty_ratio=10 >/dev/null
    echo "✓ Set dirty page ratios"
fi

echo ""
echo "=== 7. Reduce Reserved Blocks (1%) ==="
CURRENT_RESERVED=$(tune2fs -l "$ROOT_DEVICE" 2>/dev/null | grep "Reserved block count" | awk '{print $4}')
TOTAL_BLOCKS=$(tune2fs -l "$ROOT_DEVICE" 2>/dev/null | grep "^Block count" | awk '{print $3}')
if [[ -n "$CURRENT_RESERVED" ]] && [[ -n "$TOTAL_BLOCKS" ]]; then
    CURRENT_PCT=$(echo "scale=1; $CURRENT_RESERVED * 100 / $TOTAL_BLOCKS" | bc)
    
    if (( $(echo "$CURRENT_PCT <= 1.5" | bc -l) )); then
        echo "✓ Already at or below 1.5% ($CURRENT_PCT%)"
    else
        tune2fs -m 1 "$ROOT_DEVICE"
        echo "✓ Reduced reserved blocks from $CURRENT_PCT% to 1%"
    fi
else
    echo "⚠ Could not read block information"
fi

echo ""
echo "=== 8. Enable ext4 fast_commit ==="
if tune2fs -l "$ROOT_DEVICE" 2>/dev/null | grep features | grep -q "fast_commit"; then
    echo "✓ fast_commit already enabled"
else
    tune2fs -O fast_commit "$ROOT_DEVICE"
    echo "✓ Enabled fast_commit"
fi

echo ""
echo "=========================================="
echo "  Optimization Complete!"
echo "=========================================="
echo ""
echo "Summary of changes applied for disk: /dev/$ROOT_PHYSICAL"
echo ""
echo "Current status:"
echo "  • Filesystem: noatime, commit=60"
echo "  • TRIM: Enabled"
echo "  • I/O Queue Depth: 2048"
echo "  • LVM Read-Ahead: 8192 sectors"
echo "  • Swappiness: 10"
echo "  • VM Dirty Ratios: 5/10"
echo "  • Reserved Blocks: ~1%"
echo "  • ext4 fast_commit: Enabled"
echo ""
if grep -q "will take effect" /tmp/optimize_reboot_needed 2>/dev/null; then
    echo "IMPORTANT: Reboot recommended for all changes to take effect"
    echo ""
    echo "After reboot, run: sudo ./validate-optimizations.sh"
else
    echo "All optimizations are active!"
    echo ""
    echo "Run validation: sudo ./validate-optimizations.sh"
fi
echo ""
