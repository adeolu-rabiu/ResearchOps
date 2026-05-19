#!/bin/bash
# ResearchOps — Phase 4 Test Suite
# NFS Shared Storage with Data Isolation
# Run from: /mnt/vmdata/researchops

PASS=0; FAIL=0; WARNS=0
GREEN='\033[0;32m'; RED='\033[0;31m'
YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

pass()   { echo -e "${GREEN}PASS${NC}  $1"; PASS=$((PASS+1)); }
fail()   { echo -e "${RED}FAIL${NC}  $1"; FAIL=$((FAIL+1)); }
warn()   { echo -e "${YELLOW}WARN${NC}  $1"; WARNS=$((WARNS+1)); }
header() { echo -e "\n${BLUE}--- $1 ---${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

run_on() {
  local ip=$1; shift
  ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@"$ip" "$@" 2>/dev/null
}

echo "=============================================="
echo " ResearchOps — Phase 4 Test Suite"
echo " NFS Shared Storage with Data Isolation"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================================="

# TEST 1: NFS server packages installed
header "TEST 1: NFS server installed on nfs-server"
PKG=$(run_on 10.0.0.14 "dpkg -l nfs-kernel-server 2>/dev/null | grep '^ii' | awk '{print \$2}'")
[ "$PKG" = "nfs-kernel-server" ] \
  && pass "nfs-kernel-server installed" \
  || fail "nfs-kernel-server not installed"

# TEST 2: NFS server service running
header "TEST 2: NFS server service running"
STATUS=$(run_on 10.0.0.14 "systemctl is-active nfs-kernel-server")
[ "$STATUS" = "active" ] \
  && pass "nfs-kernel-server active" \
  || fail "nfs-kernel-server status=$STATUS"

# TEST 3: /data exported correctly
header "TEST 3: /data exported to 10.0.0.0/24"
EXPORT=$(run_on 10.0.0.14 "showmount -e localhost 2>/dev/null")
echo "$EXPORT" | grep -q "/data" \
  && pass "NFS exports /data: $EXPORT" \
  || fail "NFS not exporting /data (got: $EXPORT)"

# TEST 4: showmount visible from central-manager
header "TEST 4: NFS export visible from central-manager"
EXPORT=$(run_on 10.0.0.11 "showmount -e 10.0.0.14 2>/dev/null")
echo "$EXPORT" | grep -q "/data" \
  && pass "showmount from central-manager shows /data" \
  || fail "showmount from central-manager failed"

# TEST 5: /data mounted on all 5 client VMs
header "TEST 5: /data mounted on all 5 client VMs"
for ip in 10.0.0.10 10.0.0.11 10.0.0.12 10.0.0.13 10.0.0.15; do
  MOUNTED=$(run_on "$ip" "findmnt -rn -T /data -S 10.0.0.14:/data -o SOURCE 2>/dev/null | head -1")
  [ -n "$MOUNTED" ] \
    && pass "$ip /data mounted: $MOUNTED" \
    || fail "$ip /data not mounted"
done

# TEST 6: /data in fstab on client VMs
header "TEST 6: NFS mount in fstab for persistence"
for ip in 10.0.0.10 10.0.0.11 10.0.0.12 10.0.0.13 10.0.0.15; do
  IN_FSTAB=$(run_on "$ip" "grep '10.0.0.14:/data' /etc/fstab 2>/dev/null")
  [ -n "$IN_FSTAB" ] \
    && pass "$ip fstab entry exists" \
    || fail "$ip fstab entry missing"
done

# TEST 7: Directory structure and permissions on NFS server
header "TEST 7: Directory structure and permissions"
declare -A EXPECTED_PERMS=(
  ["/data/projects/physics"]="770"
  ["/data/projects/biology"]="770"
  ["/data/projects/chemistry"]="770"
  ["/data/shared"]="775"
  ["/data/containers"]="755"
  ["/data/outputs"]="1777"
  ["/data/logs"]="700"
)
for dir in "${!EXPECTED_PERMS[@]}"; do
  PERM=$(run_on 10.0.0.14 \
    "stat -c '%a' $dir 2>/dev/null")
  EXPECTED="${EXPECTED_PERMS[$dir]}"
  [ "$PERM" = "$EXPECTED" ] \
    && pass "$dir permissions=$PERM" \
    || fail "$dir permissions=$PERM (expected $EXPECTED)"
done

# TEST 8: Research groups exist on all nodes
header "TEST 8: Research groups consistent across all nodes"
for grp in physics-grp biology-grp chem-grp research-grp; do
  for ip in 10.0.0.10 10.0.0.11 10.0.0.12 10.0.0.13 10.0.0.14 10.0.0.15; do
    GID=$(run_on "$ip" "getent group $grp 2>/dev/null | cut -d: -f3")
    [ -n "$GID" ] \
      && pass "$ip $grp GID=$GID" \
      || fail "$ip $grp not found"
  done
done

# TEST 9: NFS shared write test — write on submit, read on execute
header "TEST 9: NFS shared storage — write on submit, read on execute"
TESTFILE="/data/shared/nfs-test-$(date +%s).txt"
TESTCONTENT="NFS test from submit-node at $(date)"

run_on 10.0.0.10 "echo '$TESTCONTENT' > $TESTFILE" >/dev/null
sleep 2

for ip in 10.0.0.12 10.0.0.13; do
  CONTENT=$(run_on "$ip" "cat $TESTFILE 2>/dev/null")
  [ "$CONTENT" = "$TESTCONTENT" ] \
    && pass "$ip read NFS file written by submit-node" \
    || fail "$ip cannot read NFS file (got: $CONTENT)"
done

run_on 10.0.0.10 "rm -f $TESTFILE" >/dev/null

# TEST 10: Per-project data isolation — physics cannot read biology
header "TEST 10: Per-project data isolation"

# Write test data
run_on 10.0.0.14 "
  echo 'physics secret' > /data/projects/physics/secret.txt
  echo 'biology secret' > /data/projects/biology/secret.txt
" >/dev/null

# physics-user can read physics
RESULT=$(run_on 10.0.0.10 \
  "su - physics-user -s /bin/bash -c 'cat /data/projects/physics/secret.txt' 2>/dev/null")
[ "$RESULT" = "physics secret" ] \
  && pass "physics-user can read /data/projects/physics" \
  || fail "physics-user cannot read /data/projects/physics (got: $RESULT)"

# physics-user cannot read biology
RESULT=$(run_on 10.0.0.10 \
  "su - physics-user -s /bin/bash -c 'cat /data/projects/biology/secret.txt' 2>&1")
echo "$RESULT" | grep -qE "Permission denied|cannot open" \
  && pass "physics-user CANNOT read /data/projects/biology — isolation enforced" \
  || fail "physics-user READ biology data — isolation BROKEN (got: $RESULT)"

# biology-user can read biology
RESULT=$(run_on 10.0.0.10 \
  "su - biology-user -s /bin/bash -c 'cat /data/projects/biology/secret.txt' 2>/dev/null")
[ "$RESULT" = "biology secret" ] \
  && pass "biology-user can read /data/projects/biology" \
  || fail "biology-user cannot read /data/projects/biology"

# biology-user cannot read physics
RESULT=$(run_on 10.0.0.10 \
  "su - biology-user -s /bin/bash -c 'cat /data/projects/physics/secret.txt' 2>&1")
echo "$RESULT" | grep -qE "Permission denied|cannot open" \
  && pass "biology-user CANNOT read /data/projects/physics — isolation enforced" \
  || fail "biology-user READ physics data — isolation BROKEN (got: $RESULT)"

# TEST 11: SIF image accessible on NFS
header "TEST 11: research-workload.sif accessible via NFS"
for ip in 10.0.0.12 10.0.0.13; do
  SIZE=$(run_on "$ip" \
    "ls -lh /data/containers/research-workload.sif 2>/dev/null | awk '{print \$5}'")
  [ -n "$SIZE" ] \
    && pass "$ip SIF on NFS: $SIZE" \
    || warn "$ip SIF not found on NFS /data/containers/"
done

# TEST 12: researcher can write to /data/outputs
header "TEST 12: researcher can write to /data/outputs"
RESULT=$(run_on 10.0.0.10 \
  "su - researcher -s /bin/bash -c \
   'echo test > /data/outputs/test-\$\$.txt && echo ok && rm /data/outputs/test-\$\$.txt' \
   2>/dev/null")
[ "$RESULT" = "ok" ] \
  && pass "researcher can write to /data/outputs" \
  || fail "researcher cannot write to /data/outputs"

# SUMMARY
echo ""
echo "=============================================="
echo " PHASE 4 TEST SUMMARY"
echo "=============================================="
echo -e " ${GREEN}PASSED:${NC}   $PASS"
echo -e " ${RED}FAILED:${NC}   $FAIL"
echo -e " ${YELLOW}WARNINGS:${NC} $WARNS"
echo "=============================================="

if [ "$FAIL" -eq 0 ]; then
  echo -e "\n${GREEN}PHASE 4 COMPLETE — safe to commit and proceed to Phase 5${NC}\n"
  exit 0
else
  echo -e "\n${RED}PHASE 4 INCOMPLETE — fix $FAIL failure(s) before committing${NC}\n"
  exit 1
fi
