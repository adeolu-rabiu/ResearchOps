#!/bin/bash
# ResearchOps — Phase 1 Test Suite
# Run from: /mnt/vmdata/researchops
# Usage:    bash tests/phase-1-test.sh

PASS=0; FAIL=0; WARNS=0
GREEN='\033[0;32m'; RED='\033[0;31m'
YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}  $1"; PASS=$((PASS+1)); }
fail() { echo -e "${RED}FAIL${NC}  $1"; FAIL=$((FAIL+1)); }
warn() { echo -e "${YELLOW}WARN${NC}  $1"; WARNS=$((WARNS+1)); }
header() { echo -e "\n${BLUE}--- $1 ---${NC}"; }

# Must run from project root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT" || { echo "Cannot find project root"; exit 1; }

echo "=============================================="
echo " ResearchOps — Phase 1 Test Suite"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo " Running from: $PROJECT_ROOT"
echo "=============================================="

# TEST 1: Terraform state
header "TEST 1: Terraform state"
COUNT=$(cd terraform && terraform state list 2>/dev/null | wc -l)
[ "$COUNT" -eq 6 ] \
  && pass "Terraform state has 6 resources" \
  || fail "Terraform state has $COUNT resources (expected 6)"

# TEST 2: All 6 VMs running in Proxmox
header "TEST 2: Proxmox VM status"
for vmid in 200 201 202 203 204 205; do
  STATUS=$(qm status $vmid 2>/dev/null | awk '{print $2}')
  [ "$STATUS" = "running" ] \
    && pass "VMID $vmid is running" \
    || fail "VMID $vmid status=$STATUS (expected running)"
done

# TEST 3: Ping all 6 VMs
header "TEST 3: Network reachability (ping)"
declare -A VM_IPS
VM_IPS["submit-node"]="10.0.0.10"
VM_IPS["central-manager"]="10.0.0.11"
VM_IPS["execute-node-1"]="10.0.0.12"
VM_IPS["execute-node-2"]="10.0.0.13"
VM_IPS["nfs-server"]="10.0.0.14"
VM_IPS["monitoring"]="10.0.0.15"

for name in "submit-node" "central-manager" "execute-node-1" \
            "execute-node-2" "nfs-server" "monitoring"; do
  ip="${VM_IPS[$name]}"
  ping -c 1 -W 3 "$ip" > /dev/null 2>&1 \
    && pass "$name ($ip) reachable" \
    || fail "$name ($ip) not reachable"
done

# TEST 4: SSH as root
header "TEST 4: SSH access (root)"
for name in "submit-node" "central-manager" "execute-node-1" \
            "execute-node-2" "nfs-server" "monitoring"; do
  ip="${VM_IPS[$name]}"
  HOSTNAME=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
    root@"$ip" "hostname -s" 2>/dev/null)
  [ "$HOSTNAME" = "$name" ] \
    && pass "SSH root@$ip hostname=$HOSTNAME" \
    || fail "SSH root@$ip failed (got '$HOSTNAME' expected '$name')"
done

# TEST 5: RAM allocation
header "TEST 5: VM RAM allocation"
declare -A MIN_RAM
MIN_RAM["10.0.0.10"]="1"
MIN_RAM["10.0.0.11"]="1"
MIN_RAM["10.0.0.12"]="3"
MIN_RAM["10.0.0.13"]="3"
MIN_RAM["10.0.0.14"]="0"
MIN_RAM["10.0.0.15"]="1"

for ip in "10.0.0.10" "10.0.0.11" "10.0.0.12" \
          "10.0.0.13" "10.0.0.14" "10.0.0.15"; do
  RAM=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
    root@"$ip" "free -g | awk '/Mem:/{print \$2}'" 2>/dev/null)
  MIN="${MIN_RAM[$ip]}"
  [ "${RAM:-0}" -ge "$MIN" ] \
    && pass "$ip RAM=${RAM}GB (min ${MIN}GB)" \
    || fail "$ip RAM=${RAM}GB below minimum ${MIN}GB"
done

# TEST 6: Disk allocation
header "TEST 6: VM disk allocation"
declare -A MIN_DISK
MIN_DISK["10.0.0.10"]="18"
MIN_DISK["10.0.0.11"]="18"
MIN_DISK["10.0.0.12"]="38"
MIN_DISK["10.0.0.13"]="38"
MIN_DISK["10.0.0.14"]="90"
MIN_DISK["10.0.0.15"]="18"

for ip in "10.0.0.10" "10.0.0.11" "10.0.0.12" \
          "10.0.0.13" "10.0.0.14" "10.0.0.15"; do
  DISK=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
    root@"$ip" "df -BG / | awk 'NR==2{print \$2}' | tr -d G" 2>/dev/null)
  MIN="${MIN_DISK[$ip]}"
  [ "${DISK:-0}" -ge "$MIN" ] \
    && pass "$ip disk=${DISK}GB (min ${MIN}GB)" \
    || fail "$ip disk=${DISK}GB below minimum ${MIN}GB"
done

# TEST 7: Internet access
header "TEST 7: Internet access from VMs"
for name in "submit-node" "central-manager" "execute-node-1" \
            "execute-node-2" "nfs-server" "monitoring"; do
  ip="${VM_IPS[$name]}"
  RESULT=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
    root@"$ip" \
    "curl -s --max-time 5 https://www.google.com -o /dev/null -w '%{http_code}'" \
    2>/dev/null)
  [ "$RESULT" = "200" ] \
    && pass "$name internet OK" \
    || warn "$name internet check returned '$RESULT'"
done

# TEST 8: Inter-VM connectivity
header "TEST 8: Inter-VM connectivity"
RESULT=$(ssh -o StrictHostKeyChecking=no root@10.0.0.10 \
  "ping -c 1 -W 2 10.0.0.11 > /dev/null 2>&1 && echo ok" 2>/dev/null)
[ "$RESULT" = "ok" ] \
  && pass "submit-node can reach central-manager" \
  || fail "submit-node cannot reach central-manager"

RESULT=$(ssh -o StrictHostKeyChecking=no root@10.0.0.12 \
  "ping -c 1 -W 2 10.0.0.14 > /dev/null 2>&1 && echo ok" 2>/dev/null)
[ "$RESULT" = "ok" ] \
  && pass "execute-node-1 can reach nfs-server" \
  || fail "execute-node-1 cannot reach nfs-server"

# TEST 9: Ansible ping
header "TEST 9: Ansible ping"
ANSIBLE_OUT=$(ansible all \
  -i ansible/inventory/hosts.ini \
  -m ping 2>&1)
SUCCESS_COUNT=$(echo "$ANSIBLE_OUT" | grep -c "SUCCESS")
FAIL_COUNT=$(echo "$ANSIBLE_OUT" | grep -c "FAILED\|UNREACHABLE")
[ "$SUCCESS_COUNT" -eq 6 ] && [ "$FAIL_COUNT" -eq 0 ] \
  && pass "Ansible ping SUCCESS on all 6 hosts" \
  || fail "Ansible ping: $SUCCESS_COUNT/6 success $FAIL_COUNT failures"

# TEST 10: Python3 available
header "TEST 10: Python3 on all VMs"
for name in "submit-node" "central-manager" "execute-node-1" \
            "execute-node-2" "nfs-server" "monitoring"; do
  ip="${VM_IPS[$name]}"
  PYVER=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
    root@"$ip" "python3 --version 2>/dev/null" 2>/dev/null)
  [ -n "$PYVER" ] \
    && pass "$name $PYVER" \
    || fail "$name python3 not found"
done

# SUMMARY
echo ""
echo "=============================================="
echo " PHASE 1 TEST SUMMARY"
echo "=============================================="
echo -e " ${GREEN}PASSED:${NC}   $PASS"
echo -e " ${RED}FAILED:${NC}   $FAIL"
echo -e " ${YELLOW}WARNINGS:${NC} $WARNS"
echo "=============================================="

if [ "$FAIL" -eq 0 ]; then
  echo -e "\n${GREEN}PHASE 1 COMPLETE — safe to commit and proceed to Phase 2${NC}\n"
  exit 0
else
  echo -e "\n${RED}PHASE 1 INCOMPLETE — fix $FAIL failure(s) before committing${NC}\n"
  exit 1
fi
