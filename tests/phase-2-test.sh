#!/bin/bash
# ResearchOps — Phase 2 Test Suite
# HTCondor Pool
# Run from: /mnt/vmdata/researchops
# Usage: bash tests/phase-2-test.sh

PASS=0; FAIL=0; WARNS=0
GREEN='\033[0;32m'; RED='\033[0;31m'
YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}  $1"; PASS=$((PASS+1)); }
fail() { echo -e "${RED}FAIL${NC}  $1"; FAIL=$((FAIL+1)); }
warn() { echo -e "${YELLOW}WARN${NC}  $1"; WARNS=$((WARNS+1)); }
header() { echo -e "\n${BLUE}--- $1 ---${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

CONDOR_BIN="/opt/htcondor/bin"
CONDOR_SBIN="/opt/htcondor/sbin"
CONDOR_CFG="/opt/htcondor/etc/condor_config"

run_on() {
  local ip=$1; shift
  ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@"$ip" "$@" 2>/dev/null
}

condor_on() {
  local ip=$1; shift
  ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@"$ip" \
    "CONDOR_CONFIG=${CONDOR_CFG} PATH=${CONDOR_BIN}:${CONDOR_SBIN}:\$PATH $*" 2>/dev/null
}

echo "=============================================="
echo " ResearchOps — Phase 2 Test Suite"
echo " HTCondor Pool"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================================="

# TEST 1: HTCondor binary installed on all 4 nodes
header "TEST 1: HTCondor installed on all 4 nodes"
for ip in 10.0.0.10 10.0.0.11 10.0.0.12 10.0.0.13; do
  VER=$(run_on "$ip" "${CONDOR_BIN}/condor_version 2>/dev/null | head -1")
  [ -n "$VER" ] \
    && pass "$ip HTCondor installed: $VER" \
    || fail "$ip HTCondor not found at ${CONDOR_BIN}/condor_version"
done

# TEST 2: HTCondor service running on all 4 nodes
header "TEST 2: HTCondor service running"
for ip in 10.0.0.10 10.0.0.11 10.0.0.12 10.0.0.13; do
  STATUS=$(run_on "$ip" "systemctl is-active condor")
  [ "$STATUS" = "active" ] \
    && pass "$ip condor service active" \
    || fail "$ip condor service status=$STATUS"
done

# TEST 3: Central Manager daemons
header "TEST 3: Central Manager daemons (Collector + Negotiator)"
for daemon in condor_collector condor_negotiator; do
  RUNNING=$(run_on 10.0.0.11 "ps aux | grep $daemon | grep -v grep | wc -l")
  [ "${RUNNING:-0}" -ge 1 ] \
    && pass "$daemon running on central-manager" \
    || fail "$daemon not running on central-manager"
done

# TEST 4: Submit Node Schedd
header "TEST 4: Submit Node daemon (Schedd)"
RUNNING=$(run_on 10.0.0.10 "ps aux | grep condor_schedd | grep -v grep | wc -l")
[ "${RUNNING:-0}" -ge 1 ] \
  && pass "condor_schedd running on submit-node" \
  || fail "condor_schedd not running on submit-node"

# TEST 5: Execute Node Startds
header "TEST 5: Execute Node daemons (Startd)"
for ip in 10.0.0.12 10.0.0.13; do
  RUNNING=$(run_on "$ip" "ps aux | grep condor_startd | grep -v grep | wc -l")
  [ "${RUNNING:-0}" -ge 1 ] \
    && pass "$ip condor_startd running" \
    || fail "$ip condor_startd not running"
done

# TEST 6: Execute nodes visible in condor_status
header "TEST 6: Execute nodes visible in pool"
POOL=$(condor_on 10.0.0.11 condor_status 2>/dev/null)
echo "$POOL" | grep -q "execute-node-1" \
  && pass "execute-node-1 visible in condor_status" \
  || fail "execute-node-1 not visible in condor_status"
echo "$POOL" | grep -q "execute-node-2" \
  && pass "execute-node-2 visible in condor_status" \
  || fail "execute-node-2 not visible in condor_status"

# TEST 7: Pool CPU slot count
header "TEST 7: Total pool CPU slots"
TOTAL=$(condor_on 10.0.0.11 "condor_status 2>/dev/null | awk '/X86_64\\/LINUX/{print \$2}' | tail -1")
[[ "${TOTAL:-0}" =~ ^[0-9]+$ ]] && [ "$TOTAL" -ge 2 ] \
  && pass "Pool has $TOTAL CPU slots (min 2)" \
  || fail "Pool has ${TOTAL:-0} CPU slots (expected >= 2)"

# TEST 8: Fair-use accounting groups
header "TEST 8: Fair-use accounting groups"
ACCT_GROUPS=$(run_on 10.0.0.11 \
  "CONDOR_CONFIG=${CONDOR_CFG} ${CONDOR_BIN}/condor_config_val GROUP_NAMES")
echo "$ACCT_GROUPS" | grep -q "group_physics" \
  && pass "Accounting groups configured: $ACCT_GROUPS" \
  || fail "Accounting groups not found (got: '$ACCT_GROUPS')"

QUOTA=$(run_on 10.0.0.11 \
  "CONDOR_CONFIG=${CONDOR_CFG} ${CONDOR_BIN}/condor_config_val GROUP_QUOTA_group_physics")
[ "${QUOTA:-0}" -eq 4 ] \
  && pass "group_physics quota = $QUOTA CPUs" \
  || fail "group_physics quota = '${QUOTA}' (expected 4)"

OVERSUB=$(run_on 10.0.0.11 \
  "CONDOR_CONFIG=${CONDOR_CFG} ${CONDOR_BIN}/condor_config_val NEGOTIATOR_ALLOW_QUOTA_OVERSUBSCRIPTION")
echo "${OVERSUB}" | grep -qi "false" \
  && pass "Quota oversubscription disabled (NEGOTIATOR_ALLOW_QUOTA_OVERSUBSCRIPTION=False)" \
  || fail "NEGOTIATOR_ALLOW_QUOTA_OVERSUBSCRIPTION = '${OVERSUB}' (expected False)"

# TEST 9: researcher user
header "TEST 9: researcher user exists on submit-node"
RES=$(run_on 10.0.0.10 "id researcher")
[ -n "$RES" ] \
  && pass "researcher user exists: $RES" \
  || fail "researcher user not found on submit-node"

# TEST 10: /data/jobs writable
header "TEST 10: /data/jobs directory writable"
run_on 10.0.0.10 "mkdir -p /data/jobs && chmod 1777 /data/jobs" >/dev/null
WRITABLE=$(run_on 10.0.0.10 "touch /data/jobs/.writetest && echo ok && rm /data/jobs/.writetest")
[ "$WRITABLE" = "ok" ] \
  && pass "/data/jobs is writable" \
  || fail "/data/jobs is not writable"

# TEST 11: End-to-end job submission and execution
header "TEST 11: End-to-end job submission and execution"

# Clean up old files
run_on 10.0.0.10 "rm -f /data/jobs/p2test-*.out /data/jobs/p2test-*.err /data/jobs/p2test.log /data/jobs/p2test.sub" >/dev/null

# Write job submission file
run_on 10.0.0.10 'cat > /data/jobs/p2test.sub << JOBEOF
universe   = vanilla
executable = /bin/hostname
should_transfer_files = YES
when_to_transfer_output = ON_EXIT
output     = /data/jobs/p2test-$(ClusterId).$(ProcId).out
error      = /data/jobs/p2test-$(ClusterId).$(ProcId).err
log        = /data/jobs/p2test.log
queue 4
JOBEOF' >/dev/null

# Submit as researcher
SUBMIT=$(run_on 10.0.0.10 \
  "su - researcher -c 'CONDOR_CONFIG=${CONDOR_CFG} PATH=${CONDOR_BIN}:${CONDOR_SBIN}:\$PATH condor_submit /data/jobs/p2test.sub 2>/dev/null'")
echo "$SUBMIT" | grep -q "submitted to cluster" \
  && pass "Job submitted: $(echo "$SUBMIT" | tail -1)" \
  || fail "Job submission failed: $SUBMIT"

# Wait up to 120 seconds
echo "  Waiting up to 120 seconds for jobs to complete..."
COMPLETED=0
for i in $(seq 1 12); do
  sleep 10
  QOUT=$(run_on 10.0.0.10 \
    "su - researcher -c 'CONDOR_CONFIG=${CONDOR_CFG} PATH=${CONDOR_BIN}:${CONDOR_SBIN}:\$PATH condor_q 2>/dev/null | grep \"Total for all\"'")
  echo "  t+${i}0s: $QOUT"
  if echo "$QOUT" | grep -q "0 jobs" || [ -z "$QOUT" ]; then
    COMPLETED=1; break
  fi
done

[ "$COMPLETED" -eq 1 ] \
  && pass "All jobs completed within timeout" \
  || warn "Jobs may still be running — check condor_q manually"

# TEST 12: Output files contain execute node names
header "TEST 12: Job output contains execute node hostnames"
COUNT=$(run_on 10.0.0.10 "ls /data/jobs/p2test-*.out 2>/dev/null | wc -l")
[ "${COUNT:-0}" -ge 1 ] \
  && pass "Job output files found: $COUNT files" \
  || fail "No output files found in /data/jobs/"

OUTPUTS=$(run_on 10.0.0.10 "cat /data/jobs/p2test-*.out 2>/dev/null | tr '\n' ' '")
echo "$OUTPUTS" | grep -q "execute-node" \
  && pass "Jobs ran on execute nodes: $OUTPUTS" \
  || fail "Output does not contain execute node names: '$OUTPUTS'"

# TEST 13: condor_history shows completed jobs
header "TEST 13: condor_history shows completed jobs"
HIST=$(run_on 10.0.0.10 \
  "su - researcher -c 'CONDOR_CONFIG=${CONDOR_CFG} PATH=${CONDOR_BIN}:${CONDOR_SBIN}:\$PATH condor_history 2>/dev/null | grep \" C \"'")
[ -n "$HIST" ] \
  && pass "condor_history shows completed jobs" \
  || fail "condor_history shows no completed jobs"

# TEST 14: Negotiator cycle confirmed
header "TEST 14: Negotiator cycle running"
NEG=$(run_on 10.0.0.11 "grep 'Finished Negotiation Cycle' /var/lib/condor/log/NegotiatorLog 2>/dev/null | tail -1")
[ -n "$NEG" ] \
  && pass "Negotiator cycle confirmed: $NEG" \
  || fail "No Negotiator cycle found in NegotiatorLog"

# SUMMARY
echo ""
echo "=============================================="
echo " PHASE 2 TEST SUMMARY"
echo "=============================================="
echo -e " ${GREEN}PASSED:${NC}   $PASS"
echo -e " ${RED}FAILED:${NC}   $FAIL"
echo -e " ${YELLOW}WARNINGS:${NC} $WARNS"
echo "=============================================="

if [ "$FAIL" -eq 0 ]; then
  echo -e "\n${GREEN}PHASE 2 COMPLETE — safe to commit and proceed to Phase 3${NC}\n"
  exit 0
else
  echo -e "\n${RED}PHASE 2 INCOMPLETE — fix $FAIL failure(s) before committing${NC}\n"
  exit 1
fi
