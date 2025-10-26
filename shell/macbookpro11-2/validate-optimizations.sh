#!/bin/bash
#
# Linux Mint SSD Optimization Script (for a MacBook Pro 2014)
# Companion script to optimize-ssd.sh script
# Checks that all optimizations are active
#

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "  SSD Optimization Validation Report"
echo "=========================================="
echo ""

PASS=0
FAIL=0
WARN=0

# Detect root device and physical disk (improved for LVM)
ROOT_DEVICE=$(findmnt -n -o SOURCE /)

# For LVM, trace back to physical device
if [[ $ROOT_DEVICE == /dev/mapper/* ]]; then
    # Get the physical volume backing this LV
    PV_DEVICE=$(sudo pvs --noheadings -o pv_name -S "vg_name=$(sudo lvs --noheadings -o vg_name $ROOT_DEVICE | tr -d ' ')" | tr -d ' ' | head -1)
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

echo "Root device: $ROOT_DEVICE"
echo "Physical disk: ${ROOT_PHYSICAL:-[detection failed]}"
echo ""

if [[ -z "$ROOT_PHYSICAL" ]]; then
    echo -e "${RED}ERROR: Could not detect physical disk${NC}"
    echo "Please manually specify the disk (e.g., sda, nvme0n1)"
    echo ""
fi

# Test 1: TRIM
echo -n "1. TRIM Status: "
if systemctl is-enabled fstrim.timer &>/dev/null && systemctl is-active fstrim.timer &>/dev/null; then
    echo -e "${GREEN}✓ PASS${NC} (enabled and active)"
    ((PASS++))
else
    echo -e "${RED}✗ FAIL${NC}"
    ((FAIL++))
fi

# Test 2: I/O Scheduler
echo -n "2. I/O Scheduler: "
if [[ -n "$ROOT_PHYSICAL" ]] && [[ -f /sys/block/$ROOT_PHYSICAL/queue/scheduler ]]; then
    SCHEDULER=$(cat /sys/block/$ROOT_PHYSICAL/queue/scheduler 2>/dev/null)
    if [[ $SCHEDULER == *"[mq-deadline]"* ]] || [[ $SCHEDULER == *"[none]"* ]]; then
        echo -e "${GREEN}✓ PASS${NC} ($(echo $SCHEDULER | grep -o '\[.*\]'))"
        ((PASS++))
    else
        echo -e "${YELLOW}⚠ WARN${NC} ($SCHEDULER)"
        ((WARN++))
    fi
else
    echo -e "${RED}✗ FAIL${NC} (cannot detect)"
    ((FAIL++))
fi

# Test 3: Filesystem Mount Options
echo -n "3. Mount Options: "
MOUNT_OPTS=$(mount | grep " / " | grep -oE "noatime|commit=[0-9]+")
if echo "$MOUNT_OPTS" | grep -q "noatime" && echo "$MOUNT_OPTS" | grep -q "commit=60"; then
    echo -e "${GREEN}✓ PASS${NC} (noatime, commit=60)"
    ((PASS++))
else
    echo -e "${RED}✗ FAIL${NC} (missing: $MOUNT_OPTS)"
    ((FAIL++))
fi

# Test 4: LVM Alignment
echo -n "4. LVM Alignment: "
if sudo pvs -o +pe_start 2>/dev/null | grep -q "1.00m"; then
    echo -e "${GREEN}✓ PASS${NC} (1MB)"
    ((PASS++))
else
    echo -e "${YELLOW}⚠ WARN${NC} (not using LVM or non-optimal)"
    ((WARN++))
fi

# Test 5: Swappiness
echo -n "5. Swappiness: "
SWAPPINESS=$(cat /proc/sys/vm/swappiness)
if [[ $SWAPPINESS -eq 10 ]]; then
    echo -e "${GREEN}✓ PASS${NC} ($SWAPPINESS)"
    ((PASS++))
else
    echo -e "${RED}✗ FAIL${NC} ($SWAPPINESS, should be 10)"
    ((FAIL++))
fi

# Test 6: I/O Queue Depth
echo -n "6. I/O Queue Depth: "
if [[ -n "$ROOT_PHYSICAL" ]] && [[ -f /sys/block/$ROOT_PHYSICAL/queue/nr_requests ]]; then
    QUEUE_DEPTH=$(cat /sys/block/$ROOT_PHYSICAL/queue/nr_requests 2>/dev/null)
    if [[ $QUEUE_DEPTH -eq 2048 ]]; then
        echo -e "${GREEN}✓ PASS${NC} (2048)"
        ((PASS++))
    else
        echo -e "${RED}✗ FAIL${NC} ($QUEUE_DEPTH, should be 2048)"
        ((FAIL++))
    fi
else
    echo -e "${RED}✗ FAIL${NC} (cannot detect)"
    ((FAIL++))
fi

# Test 7: LVM Read-Ahead
echo -n "7. LVM Read-Ahead: "
if sudo lvdisplay "$ROOT_DEVICE" &>/dev/null; then
    READAHEAD=$(sudo lvs -o lv_read_ahead --noheadings "$ROOT_DEVICE" 2>/dev/null | tr -d ' ')
    if [[ $READAHEAD == "4.00m" ]] || [[ $READAHEAD == "8192" ]]; then
        echo -e "${GREEN}✓ PASS${NC} ($READAHEAD = 8192 sectors)"
        ((PASS++))
    else
        echo -e "${RED}✗ FAIL${NC} ($READAHEAD)"
        ((FAIL++))
    fi
else
    echo -e "${YELLOW}⊘ SKIP${NC} (not using LVM)"
    ((WARN++))
fi

# Test 8: VM Dirty Ratios
echo -n "8. VM Dirty Ratios: "
DIRTY_BG=$(sysctl -n vm.dirty_background_ratio)
DIRTY=$(sysctl -n vm.dirty_ratio)
if [[ $DIRTY_BG -eq 5 ]] && [[ $DIRTY -eq 10 ]]; then
    echo -e "${GREEN}✓ PASS${NC} (5/10)"
    ((PASS++))
else
    echo -e "${RED}✗ FAIL${NC} ($DIRTY_BG/$DIRTY, should be 5/10)"
    ((FAIL++))
fi

# Test 9: Reserved Blocks
echo -n "9. Reserved Blocks: "
RESERVED=$(sudo tune2fs -l "$ROOT_DEVICE" 2>/dev/null | grep "Reserved block count" | awk '{print $4}')
TOTAL=$(sudo tune2fs -l "$ROOT_DEVICE" 2>/dev/null | grep "^Block count" | awk '{print $3}')
if [[ -n "$RESERVED" ]] && [[ -n "$TOTAL" ]]; then
    PCT=$(echo "scale=2; $RESERVED * 100 / $TOTAL" | bc)
    if (( $(echo "$PCT <= 1.5" | bc -l) )); then
        echo -e "${GREEN}✓ PASS${NC} (${PCT}%)"
        ((PASS++))
    else
        echo -e "${RED}✗ FAIL${NC} (${PCT}%, should be ~1%)"
        ((FAIL++))
    fi
else
    echo -e "${RED}✗ FAIL${NC} (cannot read)"
    ((FAIL++))
fi

# Test 10: fast_commit
echo -n "10. ext4 fast_commit: "
if sudo tune2fs -l "$ROOT_DEVICE" 2>/dev/null | grep features | grep -q "fast_commit"; then
    echo -e "${GREEN}✓ PASS${NC}"
    ((PASS++))
else
    echo -e "${RED}✗ FAIL${NC}"
    ((FAIL++))
fi

# Test 11: udev rule exists
echo -n "11. udev Queue Rule: "
if [[ -f /etc/udev/rules.d/60-queue-depth.rules ]]; then
    echo -e "${GREEN}✓ PASS${NC} (persistent)"
    ((PASS++))
else
    echo -e "${YELLOW}⚠ WARN${NC} (not persistent)"
    ((WARN++))
fi

echo ""
echo "=========================================="
echo "  Performance Test"
echo "=========================================="
echo ""
echo "Running 100MB write test..."
dd if=/dev/zero of=/tmp/test_write bs=1M count=100 conv=fdatasync 2>&1 | grep -E "copied|MB/s"
rm -f /tmp/test_write
echo ""

echo "=========================================="
echo "  Summary"
echo "=========================================="
echo -e "${GREEN}Passed: $PASS${NC}"
if [[ $FAIL -gt 0 ]]; then
    echo -e "${RED}Failed: $FAIL${NC}"
fi
if [[ $WARN -gt 0 ]]; then
    echo -e "${YELLOW}Warnings: $WARN${NC}"
fi
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}✓ All critical optimizations active!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some optimizations failed - review output above${NC}"
    exit 1
fi
