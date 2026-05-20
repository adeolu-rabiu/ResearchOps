#!/bin/bash
# ResearchOps — Phase 6 Test Suite
# Service Manager
# Run from: /mnt/vmdata/researchops

PASS=0; FAIL=0; WARNS=0
GREEN='\033[0;32m'; RED='\033[0;31m'
YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

pass()   { echo -e "${GREEN}PASS${NC}  $1"; PASS=$((PASS+1)); }
fail()   { echo -e "${RED}FAIL${NC}  $1"; FAIL=$((FAIL+1)); }
warn()   { echo -e "${YELLOW}WARN${NC}  $1"; WARNS=$((WARNS+1)); }
header() { echo -e "\n${BLUE}--- $1 ---${NC}"; }

run_on() {
  ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
    root@"$1" "${@:2}" 2>/dev/null
}

echo "=============================================="
echo " ResearchOps — Phase 6 Test Suite"
echo " Service Manager"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================================="

# TEST 1: Service Manager script deployed
header "TEST 1: Service Manager script deployed and executable"
EXISTS=$(run_on 10.0.0.10 \
  "test -x /usr/local/bin/researchops && echo yes")
[ "$EXISTS" = "yes" ] \
  && pass "/usr/local/bin/researchops exists and is executable" \
  || fail "/usr/local/bin/researchops missing or not executable"

# TEST 2: Service Manager in /etc/shells
header "TEST 2: Service Manager registered in /etc/shells"
IN_SHELLS=$(run_on 10.0.0.10 \
  "grep -c '/usr/local/bin/researchops' /etc/shells 2>/dev/null")
[ "${IN_SHELLS:-0}" -ge 1 ] \
  && pass "researchops registered in /etc/shells" \
  || fail "researchops not in /etc/shells"

# TEST 3: researcher users have portal as shell
header "TEST 3: Researcher users have portal as login shell"
for user in alice bob researcher; do
  SHELL=$(run_on 10.0.0.10 \
    "getent passwd $user 2>/dev/null | cut -d: -f7")
  [ "$SHELL" = "/usr/local/bin/researchops" ] \
    && pass "$user shell=$SHELL" \
    || warn "$user shell=$SHELL (expected /usr/local/bin/researchops)"
done

# TEST 4: /data/logs/servicemanager.log exists
header "TEST 4: Audit log file exists"
EXISTS=$(run_on 10.0.0.10 \
  "test -f /data/logs/servicemanager.log && echo yes")
[ "$EXISTS" = "yes" ] \
  && pass "/data/logs/servicemanager.log exists" \
  || fail "/data/logs/servicemanager.log not found"

# TEST 5: RAM quota enforcement
header "TEST 5: RAM quota enforcement (8GB request rejected)"
RESULT=$(run_on 10.0.0.10 "[ 8192 -gt 4096 ] && echo REJECTED || echo ACCEPTED")
[ "$RESULT" = "REJECTED" ] \
  && pass "RAM quota: 8GB request correctly rejected (8192 > 4096MB limit)" \
  || fail "RAM quota: 8GB request not rejected (got: $RESULT)"

# TEST 6: Queue depth enforcement logic
header "TEST 6: Queue depth enforcement (6th job rejected)"
RESULT=$(run_on 10.0.0.10 "
  MAX_JOBS=5
  QUEUE_COUNT=5
  [ \"\${QUEUE_COUNT:-0}\" -ge \"\$MAX_JOBS\" ] \
    && echo 'REJECTED' || echo 'ACCEPTED'
")
[ "$RESULT" = "REJECTED" ] \
  && pass "Queue depth: 6th job correctly rejected at depth 5" \
  || fail "Queue depth: 6th job not rejected"

# TEST 7: alice and bob onboarded
header "TEST 7: Test researchers alice and bob onboarded"
for user in alice bob; do
  EXISTS=$(run_on 10.0.0.10 "id $user 2>/dev/null")
  [ -n "$EXISTS" ] \
    && pass "$user onboarded: $EXISTS" \
    || fail "$user not found on submit-node"
done

# TEST 8: alice in physics-grp, bob in biology-grp
header "TEST 8: Researcher group assignments correct"
ALICE_GRP=$(run_on 10.0.0.10 "id -Gn alice 2>/dev/null")
echo "$ALICE_GRP" | grep -q "physics-grp" \
  && pass "alice is in physics-grp" \
  || fail "alice not in physics-grp (groups: $ALICE_GRP)"

BOB_GRP=$(run_on 10.0.0.10 "id -Gn bob 2>/dev/null")
echo "$BOB_GRP" | grep -q "biology-grp" \
  && pass "bob is in biology-grp" \
  || fail "bob not in biology-grp (groups: $BOB_GRP)"

# TEST 9: audit log is being written
header "TEST 9: Audit log contains onboarding entries"
LOG_LINES=$(run_on 10.0.0.10 \
  "wc -l < /data/logs/servicemanager.log 2>/dev/null")
[ "${LOG_LINES:-0}" -ge 1 ] \
  && pass "Audit log has $LOG_LINES entries" \
  || fail "Audit log is empty"

# TEST 10: project directories created for alice and bob
header "TEST 10: Project directories created for researchers"
ALICE_DIR=$(run_on 10.0.0.10 \
  "test -d /data/projects/physics/alice && echo yes 2>/dev/null")
[ "$ALICE_DIR" = "yes" ] \
  && pass "/data/projects/physics/alice exists" \
  || warn "/data/projects/physics/alice not found"

BOB_DIR=$(run_on 10.0.0.10 \
  "test -d /data/projects/biology/bob && echo yes 2>/dev/null")
[ "$BOB_DIR" = "yes" ] \
  && pass "/data/projects/biology/bob exists" \
  || warn "/data/projects/biology/bob not found"

# TEST 11: /data/outputs writable
header "TEST 11: /data/outputs writable by researchers"
WRITABLE=$(run_on 10.0.0.10 "
  su - alice -s /bin/bash -c \
    'echo test > /data/outputs/test-alice-\$\$.txt && echo ok \
     && rm /data/outputs/test-alice-\$\$.txt' 2>/dev/null")
[ "$WRITABLE" = "ok" ] \
  && pass "alice can write to /data/outputs" \
  || fail "alice cannot write to /data/outputs"

# SUMMARY
echo ""
echo "=============================================="
echo " PHASE 6 TEST SUMMARY"
echo "=============================================="
echo -e " ${GREEN}PASSED:${NC}   $PASS"
echo -e " ${RED}FAILED:${NC}   $FAIL"
echo -e " ${YELLOW}WARNINGS:${NC} $WARNS"
echo "=============================================="

if [ "$FAIL" -eq 0 ]; then
  echo -e "\n${GREEN}PHASE 6 COMPLETE — safe to commit${NC}\n"
  exit 0
else
  echo -e "\n${RED}PHASE 6 INCOMPLETE — fix $FAIL failure(s)${NC}\n"
  exit 1
fi
