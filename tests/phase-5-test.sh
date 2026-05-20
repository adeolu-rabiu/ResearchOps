#!/bin/bash
# ResearchOps — Phase 5 Test Suite
# Prometheus + Grafana + SLI/SLO Observability
# Run from: /mnt/vmdata/researchops

PASS=0; FAIL=0; WARNS=0
GREEN='\033[0;32m'; RED='\033[0;31m'
YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

pass()   { echo -e "${GREEN}PASS${NC}  $1"; PASS=$((PASS+1)); }
fail()   { echo -e "${RED}FAIL${NC}  $1"; FAIL=$((FAIL+1)); }
warn()   { echo -e "${YELLOW}WARN${NC}  $1"; WARNS=$((WARNS+1)); }
header() { echo -e "\n${BLUE}--- $1 ---${NC}"; }

PROM="http://10.0.0.15:9090"
GRAF="http://10.0.0.15:3000"
ALERT="http://10.0.0.15:9093"
MON="10.0.0.15"

run_on() {
  ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@"$1" \
    "${@:2}" 2>/dev/null
}

prom_query() {
  curl -s --max-time 10 \
    "${PROM}/api/v1/query?query=$(python3 -c \
    "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" \
    "$1")" 2>/dev/null
}

echo "=============================================="
echo " ResearchOps — Phase 5 Test Suite"
echo " Prometheus + Grafana + SLI/SLO"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================================="

# TEST 1: node_exporter running on all 6 VMs
header "TEST 1: node_exporter installed and running on all 6 VMs"
for ip in 10.0.0.10 10.0.0.11 10.0.0.12 10.0.0.13 10.0.0.14 10.0.0.15; do
  STATUS=$(run_on "$ip" "systemctl is-active node_exporter 2>/dev/null")
  [ "$STATUS" = "active" ] \
    && pass "$ip node_exporter active" \
    || fail "$ip node_exporter status=$STATUS"
done

# TEST 2: node_exporter port 9100 responding
header "TEST 2: node_exporter metrics endpoint responding"
for ip in 10.0.0.10 10.0.0.11 10.0.0.12 10.0.0.13 10.0.0.14 10.0.0.15; do
  RESP=$(curl -s --max-time 5 http://$ip:9100/metrics 2>/dev/null | head -1)
  [ -n "$RESP" ] \
    && pass "$ip :9100 responding" \
    || fail "$ip :9100 not responding"
done

# TEST 3: HTCondor exporter running on central-manager
header "TEST 3: HTCondor exporter running on central-manager"
STATUS=$(run_on 10.0.0.11 "systemctl is-active htcondor-exporter 2>/dev/null")
[ "$STATUS" = "active" ] \
  && pass "htcondor-exporter active on central-manager" \
  || fail "htcondor-exporter status=$STATUS"

RESP=$(curl -s --max-time 5 http://10.0.0.11:9313/metrics 2>/dev/null | \
  grep -c "htcondor_")
[ "${RESP:-0}" -ge 1 ] \
  && pass "HTCondor metrics endpoint responding: $RESP metrics" \
  || fail "HTCondor metrics endpoint not responding"

# TEST 4: Docker containers running on monitoring VM
header "TEST 4: Docker containers running on monitoring VM"
for svc in prometheus grafana alertmanager; do
  STATUS=$(run_on "$MON" \
    "docker inspect --format='{{.State.Status}}' $svc 2>/dev/null")
  [ "$STATUS" = "running" ] \
    && pass "$svc container running" \
    || fail "$svc container status=$STATUS"
done

# TEST 5: Prometheus health check
header "TEST 5: Prometheus health endpoint"
HEALTH=$(curl -s --max-time 10 "${PROM}/-/healthy" 2>/dev/null)
echo "$HEALTH" | grep -qi "healthy" \
  && pass "Prometheus healthy: $HEALTH" \
  || fail "Prometheus not healthy (got: $HEALTH)"

# TEST 6: All scrape targets UP
header "TEST 6: All Prometheus scrape targets showing UP"
TARGETS=$(curl -s --max-time 10 \
  "${PROM}/api/v1/targets" 2>/dev/null)
TOTAL=$(echo "$TARGETS" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); \
   print(len(d.get('data',{}).get('activeTargets',[])))" 2>/dev/null)
UP=$(echo "$TARGETS" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); \
   print(sum(1 for t in d.get('data',{}).get('activeTargets',[]) \
   if t.get('health')=='up'))" 2>/dev/null)

[ "${TOTAL:-0}" -ge 7 ] \
  && pass "Prometheus has $TOTAL scrape targets configured" \
  || fail "Prometheus has ${TOTAL:-0} targets (expected >= 7)"

[ "${UP:-0}" -eq "${TOTAL:-0}" ] \
  && pass "All $UP/$TOTAL targets are UP" \
  || fail "$UP/$TOTAL targets are UP (some targets DOWN)"

# TEST 7: All 6 node exporters UP in Prometheus
header "TEST 7: All 6 node exporter targets UP in Prometheus"
for node in "submit-node:9100" "central-manager:9100" \
            "execute-node-1:9100" "execute-node-2:9100" \
            "nfs-server:9100" "monitoring:9100"; do
  STATE=$(echo "$TARGETS" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for t in d.get('data',{}).get('activeTargets',[]):
    if t.get('labels',{}).get('instance','') == '$node':
        print(t.get('health','unknown'))
        break
else:
    print('not_found')
" 2>/dev/null)
  [ "$STATE" = "up" ] \
    && pass "$node state=up" \
    || fail "$node state=$STATE"
done

# TEST 8: Grafana reachable
header "TEST 8: Grafana reachable at :3000"
HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
  --max-time 10 "${GRAF}" 2>/dev/null)
[[ "$HTTP" =~ ^(200|302)$ ]] \
  && pass "Grafana HTTP $HTTP" \
  || fail "Grafana HTTP $HTTP (expected 200 or 302)"

# TEST 9: Grafana Prometheus datasource connected
header "TEST 9: Grafana Prometheus datasource connected"
DS=$(curl -s --max-time 10 -u admin:htcondorsre \
  "${GRAF}/api/datasources" 2>/dev/null)
# Provisioned datasources may show as type or url match
echo "$DS" | grep -qiE "prometheus|Prometheus" \
  && pass "Grafana has Prometheus datasource configured" \
  || {
    # Try the health check endpoint instead
    DS_HEALTH=$(curl -s --max-time 10 -u admin:htcondorsre \
      "${GRAF}/api/datasources/proxy/uid/prometheus/api/v1/query?query=up" \
      2>/dev/null)
    PROM_DIRECT=$(curl -s --max-time 10 -u admin:htcondorsre \
      "${GRAF}/api/datasources/name/Prometheus" 2>/dev/null)
    echo "$PROM_DIRECT" | grep -qi "prometheus" \
      && pass "Grafana Prometheus datasource found via name lookup" \
      || fail "Grafana Prometheus datasource not found (got: $DS)"
  }

# TEST 10: SLI recording rules return values
header "TEST 10: SLI recording rules return values"
for rule in \
  "htcondor:job_submission_success_rate:5m" \
  "htcondor:error_budget_remaining:30d" \
  "node:cpu_usage:5m" \
  "node:memory_usage:current"; do

  RESULT=$(prom_query "$rule")
  COUNT=$(echo "$RESULT" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); \
     print(len(d.get('data',{}).get('result',[])))" 2>/dev/null)

  [ "${COUNT:-0}" -ge 1 ] \
    && pass "Rule $rule returns $COUNT series" \
    || fail "Rule $rule returns no data"
done

# TEST 11: Alertmanager reachable
header "TEST 11: Alertmanager reachable at :9093"
HEALTH=$(curl -s --max-time 10 \
  "${ALERT}/-/healthy" 2>/dev/null)
echo "$HEALTH" | grep -qi "ok\|healthy" \
  && pass "Alertmanager healthy" \
  || fail "Alertmanager not healthy (got: $HEALTH)"

# TEST 12: Prometheus data retention configured
header "TEST 12: Prometheus 30-day retention configured"
FLAGS=$(curl -s --max-time 10 \
  "${PROM}/api/v1/status/flags" 2>/dev/null)
echo "$FLAGS" | grep -q "30d" \
  && pass "Prometheus 30-day retention configured" \
  || warn "Could not confirm 30d retention from flags endpoint"

# SUMMARY
echo ""
echo "=============================================="
echo " PHASE 5 TEST SUMMARY"
echo "=============================================="
echo -e " ${GREEN}PASSED:${NC}   $PASS"
echo -e " ${RED}FAILED:${NC}   $FAIL"
echo -e " ${YELLOW}WARNINGS:${NC} $WARNS"
echo "=============================================="

if [ "$FAIL" -eq 0 ]; then
  echo -e "\n${GREEN}PHASE 5 COMPLETE — safe to commit${NC}\n"
  exit 0
else
  echo -e "\n${RED}PHASE 5 INCOMPLETE — fix $FAIL failure(s)${NC}\n"
  exit 1
fi
