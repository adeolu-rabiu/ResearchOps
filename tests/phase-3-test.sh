#!/bin/bash
# ResearchOps — Phase 3 Test Suite
# Apptainer + Docker Container Isolation
# Run from: /mnt/vmdata/researchops
# Usage: bash tests/phase-3-test.sh

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

CONDOR_BIN="/opt/htcondor/bin"
CONDOR_SBIN="/opt/htcondor/sbin"
CONDOR_CFG="/opt/htcondor/etc/condor_config"

SUBMIT_NODE="10.0.0.10"
CENTRAL_MANAGER="10.0.0.11"
EXECUTE_NODES=("10.0.0.12" "10.0.0.13")

SIF_PATH="/data/containers/research-workload.sif"
WRAPPER="/usr/local/bin/run-apptainer-job"

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
echo " ResearchOps — Phase 3 Test Suite"
echo " Apptainer + Docker Container Isolation"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================================="

# TEST 1: Apptainer installed on execute nodes
header "TEST 1: Apptainer installed on execute nodes"
for ip in "${EXECUTE_NODES[@]}"; do
  VER=$(run_on "$ip" "apptainer --version 2>/dev/null")
  [ -n "$VER" ] \
    && pass "$ip Apptainer: $VER" \
    || fail "$ip Apptainer not found"
done

# TEST 2: Apptainer installed on submit-node
header "TEST 2: Apptainer installed on submit-node"
VER=$(run_on "$SUBMIT_NODE" "apptainer --version 2>/dev/null")
[ -n "$VER" ] \
  && pass "submit-node Apptainer: $VER" \
  || fail "submit-node Apptainer not found"

# TEST 3: Docker installed on submit-node
header "TEST 3: Docker installed on submit-node"
VER=$(run_on "$SUBMIT_NODE" "docker --version 2>/dev/null")
[ -n "$VER" ] \
  && pass "Docker: $VER" \
  || fail "Docker not found on submit-node"

# TEST 4: Docker service running
header "TEST 4: Docker service running"
STATUS=$(run_on "$SUBMIT_NODE" "systemctl is-active docker 2>/dev/null")
[ "$STATUS" = "active" ] \
  && pass "Docker service active" \
  || fail "Docker service status=$STATUS"

# TEST 5: HTCondor Apptainer wrapper exists on execute nodes
header "TEST 5: HTCondor Apptainer wrapper exists on execute nodes"
for ip in "${EXECUTE_NODES[@]}"; do
  WRAPPER_OK=$(run_on "$ip" "test -x ${WRAPPER} && echo yes")
  [ "$WRAPPER_OK" = "yes" ] \
    && pass "$ip run-apptainer-job wrapper installed and executable" \
    || fail "$ip run-apptainer-job wrapper missing or not executable"
done

# TEST 6: /data/containers directory exists
header "TEST 6: /data/containers directory exists"
for ip in "$SUBMIT_NODE" "${EXECUTE_NODES[@]}"; do
  EXISTS=$(run_on "$ip" "test -d /data/containers && echo yes")
  [ "$EXISTS" = "yes" ] \
    && pass "$ip /data/containers exists" \
    || fail "$ip /data/containers not found"
done

# TEST 7: SIF image exists on submit and execute nodes
header "TEST 7: research-workload.sif exists"
for ip in "$SUBMIT_NODE" "${EXECUTE_NODES[@]}"; do
  SIZE=$(run_on "$ip" "ls -lh ${SIF_PATH} 2>/dev/null | awk '{print \$5}'")
  [ -n "$SIZE" ] \
    && pass "$ip SIF exists: $SIZE" \
    || fail "$ip SIF not found at ${SIF_PATH}"
done

# TEST 8: Direct Apptainer run on execute nodes
header "TEST 8: Direct Apptainer run on execute nodes"
for ip in "${EXECUTE_NODES[@]}"; do
  OUT=$(run_on "$ip" "apptainer run ${SIF_PATH} 2>/dev/null")
  echo "$OUT" | grep -q "Result" \
    && pass "$ip direct Apptainer run: $(echo "$OUT" | grep Result | tail -1)" \
    || fail "$ip direct Apptainer run failed (output: $OUT)"
done

# TEST 9: SIF image contains numpy and scipy
header "TEST 9: SIF image contains numpy and scipy"
OUT=$(run_on "10.0.0.12" \
  "apptainer exec ${SIF_PATH} python3 -c 'import numpy,scipy; print(numpy.__version__, scipy.__version__)' 2>/dev/null")
[ -n "$OUT" ] \
  && pass "SIF contains numpy and scipy: $OUT" \
  || fail "SIF missing numpy or scipy (output: $OUT)"

# TEST 10: researcher UID consistent across all nodes
header "TEST 10: researcher user UID consistent across all nodes"
REF_UID=$(run_on "$SUBMIT_NODE" "id -u researcher 2>/dev/null")
[ -n "$REF_UID" ] \
  && pass "submit-node researcher UID=$REF_UID" \
  || fail "researcher user not found on submit-node"

for ip in "$CENTRAL_MANAGER" "${EXECUTE_NODES[@]}" 10.0.0.14 10.0.0.15; do
  NODE_UID=$(run_on "$ip" "id -u researcher 2>/dev/null")
  [ "$NODE_UID" = "$REF_UID" ] \
    && pass "$ip researcher UID=$NODE_UID matches" \
    || fail "$ip researcher UID=$NODE_UID (expected $REF_UID)"
done

# TEST 11: Apptainer config and wrapper accessible
header "TEST 11: Apptainer config and wrapper accessible on execute nodes"
for ip in "${EXECUTE_NODES[@]}"; do
  EXISTS=$(run_on "$ip" \
    "test -f /etc/apptainer/apptainer.conf && test -x ${WRAPPER} && echo yes")
  [ "$EXISTS" = "yes" ] \
    && pass "$ip Apptainer config and wrapper accessible" \
    || fail "$ip Apptainer config or wrapper missing"
done

# TEST 12: HTCondor pool has both execute nodes visible
header "TEST 12: HTCondor pool has both execute nodes visible"
POOL=$(condor_on "$CENTRAL_MANAGER" "condor_status")
echo "$POOL" | grep -q "execute-node-1" \
  && pass "execute-node-1 visible in condor_status" \
  || fail "execute-node-1 not visible in condor_status"

echo "$POOL" | grep -q "execute-node-2" \
  && pass "execute-node-2 visible in condor_status" \
  || fail "execute-node-2 not visible in condor_status"

TOTAL=$(condor_on "$CENTRAL_MANAGER" "condor_status | awk '/X86_64\\/LINUX/{print \$2}' | tail -1")
[[ "${TOTAL:-0}" =~ ^[0-9]+$ ]] && [ "$TOTAL" -ge 2 ] \
  && pass "Pool has $TOTAL CPU slots" \
  || fail "Pool has ${TOTAL:-0} CPU slots (expected >= 2)"

# TEST 13: End-to-end containerised job via HTCondor wrapper
header "TEST 13: End-to-end containerised job submission through wrapper"

run_on "$SUBMIT_NODE" "rm -f /home/researcher/p3test-*.out /home/researcher/p3test-*.err /home/researcher/p3test.log /home/researcher/p3test.sub" >/dev/null

run_on "$SUBMIT_NODE" "cat > /home/researcher/p3test.sub << 'JOBEOF'
universe                 = vanilla
executable               = /usr/local/bin/run-apptainer-job
arguments                = research-workload.sif

should_transfer_files    = YES
transfer_executable      = False
when_to_transfer_output  = ON_EXIT
transfer_input_files     = /data/containers/research-workload.sif

output                   = p3test-\$(ClusterId).\$(ProcId).out
error                    = p3test-\$(ClusterId).\$(ProcId).err
log                      = p3test.log

request_cpus             = 1
request_memory           = 512MB

queue 4
JOBEOF
chown researcher:researcher /home/researcher/p3test.sub" >/dev/null

# Remove old jobs first to avoid false positives
condor_on "$SUBMIT_NODE" "condor_rm -all || true" >/dev/null
sleep 3

SUBMIT=$(run_on "$SUBMIT_NODE" \
  "su - researcher -c 'CONDOR_CONFIG=${CONDOR_CFG} PATH=${CONDOR_BIN}:${CONDOR_SBIN}:\$PATH cd /home/researcher && condor_submit p3test.sub 2>/dev/null'")

echo "$SUBMIT" | grep -q "submitted to cluster" \
  && pass "Containerised job submitted: $(echo "$SUBMIT" | tail -1)" \
  || fail "Containerised job submission failed: $SUBMIT"

echo "  Waiting up to 120 seconds for jobs to complete..."
COMPLETED=0
for i in $(seq 1 12); do
  sleep 10
  QOUT=$(run_on "$SUBMIT_NODE" \
    "su - researcher -c 'CONDOR_CONFIG=${CONDOR_CFG} PATH=${CONDOR_BIN}:${CONDOR_SBIN}:\$PATH condor_q 2>/dev/null | grep \"Total for all\"'")
  echo "  t+${i}0s: $QOUT"
  if echo "$QOUT" | grep -q "0 jobs" || [ -z "$QOUT" ]; then
    COMPLETED=1
    break
  fi
done

[ "$COMPLETED" -eq 1 ] \
  && pass "All containerised jobs completed within timeout" \
  || warn "Jobs may still be running — check condor_q manually"

# TEST 14: Container job output contains NumPy Result
header "TEST 14: Container job output contains NumPy Result"
COUNT=$(run_on "$SUBMIT_NODE" "ls /home/researcher/p3test-*.out 2>/dev/null | wc -l")
[ "${COUNT:-0}" -ge 1 ] \
  && pass "Output files found: $COUNT files" \
  || fail "No output files found in /home/researcher/"

OUTPUTS=$(run_on "$SUBMIT_NODE" "cat /home/researcher/p3test-*.out 2>/dev/null")
echo "$OUTPUTS" | grep -q "Result" \
  && pass "Container output contains NumPy Result" \
  || fail "Output missing NumPy Result (got: $OUTPUTS)"

# TEST 15: Jobs ran on execute nodes
header "TEST 15: Jobs ran on execute nodes"
echo "$OUTPUTS" | grep -q "execute-node" \
  && pass "Jobs ran on execute nodes: $(echo "$OUTPUTS" | grep -o 'execute-node-[0-9]' | sort -u | tr '\n' ' ')" \
  || fail "Cannot confirm execute node from hostname output: $OUTPUTS"

# TEST 16: No residual Apptainer processes
header "TEST 16: No residual Apptainer processes on execute nodes"
sleep 10
for ip in "${EXECUTE_NODES[@]}"; do
  COUNT=$(run_on "$ip" "ps aux | grep apptainer | grep -v grep | wc -l")
  [ "${COUNT:-0}" -eq 0 ] \
    && pass "$ip no residual Apptainer processes" \
    || fail "$ip has $COUNT residual Apptainer processes"
done

# TEST 17: condor_history confirms completed container jobs
header "TEST 17: condor_history confirms completed container jobs"
HIST=$(run_on "$SUBMIT_NODE" \
  "su - researcher -c 'CONDOR_CONFIG=${CONDOR_CFG} PATH=${CONDOR_BIN}:${CONDOR_SBIN}:\$PATH condor_history 2>/dev/null | grep \" C \" | head'")
[ -n "$HIST" ] \
  && pass "condor_history shows completed jobs" \
  || fail "condor_history shows no completed jobs"

# SUMMARY
echo ""
echo "=============================================="
echo " PHASE 3 TEST SUMMARY"
echo "=============================================="
echo -e " ${GREEN}PASSED:${NC}   $PASS"
echo -e " ${RED}FAILED:${NC}   $FAIL"
echo -e " ${YELLOW}WARNINGS:${NC} $WARNS"
echo "=============================================="

if [ "$FAIL" -eq 0 ]; then
  echo -e "\n${GREEN}PHASE 3 COMPLETE — safe to commit and proceed to Phase 4${NC}\n"
  exit 0
else
  echo -e "\n${RED}PHASE 3 INCOMPLETE — fix $FAIL failure(s) before committing${NC}\n"
  exit 1
fi
