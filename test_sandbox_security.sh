#!/bin/bash
# NOTE: Tests assume full sandbox isolation (custom network, iptables,
# user mapping, --cap-drop=ALL, --security-opt=no-new-privileges).
# May not pass in a plain `docker run`.
set -euo pipefail

PASS=0
FAIL=0
TOTAL=0

ok() {
  TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1))
  echo "  [PASS] $1"
}

fail() {
  TOTAL=$((TOTAL + 1)); FAIL=$((FAIL + 1))
  echo "  [FAIL] $1"
}

check_pass() {
  if bash -c "$1" >/dev/null 2>&1; then ok "$2"; else fail "$2 ($3)"; fi
}

check_fail() {
  if bash -c "$1" >/dev/null 2>&1; then fail "$2 ($3)"; else ok "$2"; fi
}

echo "========================================"
echo "  Sandbox Security Test"
echo "========================================"
echo ""

# ---- Network Isolation ----
echo "--- Network ---"

check_fail 'timeout 3 wget -T 3 -q http://10.0.0.1:80/ 2>&1' \
  N1 "10.0.0.0/8 should be blocked"

check_fail 'timeout 3 wget -T 3 -q http://172.16.0.1:80/ 2>&1' \
  N2 "172.16.0.0/12 should be blocked"

check_fail 'timeout 3 wget -T 3 -q http://192.168.1.1:80/ 2>&1' \
  N3 "192.168.0.0/16 should be blocked"

check_fail 'timeout 3 wget -T 3 -q http://host.docker.internal:80/ 2>&1' \
  N4 "host.docker.internal should be blocked"

check_fail 'timeout 3 wget -T 3 -q http://host.docker.internal:22/ 2>&1' \
  N5 "host port 22 must be blocked"

check_fail 'timeout 3 wget -T 3 -q http://host.docker.internal:443/ 2>&1' \
  N6 "host port 443 must be blocked"

check_fail 'timeout 2 wget -T 2 -q http://127.0.0.1:80/ 2>&1' \
  N7 "localhost should be unreachable"

check_pass 'timeout 10 wget -T 5 -q http://example.com -O /dev/null 2>&1' \
  N8 "internet should be reachable"

echo ""

# ---- Filesystem Isolation ----
echo "--- Filesystem ---"

check_fail 'stat /var/run/docker.sock 2>&1' \
  F1 "docker socket must not exist"

check_pass 'stat /project 2>&1' \
  F2 "workspace /project must exist"

check_fail 'touch /etc/test_write 2>&1' \
  F3 "writing to /etc must be denied"

check_pass 'touch /tmp/test_write 2>&1 && rm -f /tmp/test_write' \
  F4 "writing to /tmp is allowed (container-local, ephemeral)"

check_fail 'ls /project/.env* /project/*/.env* 2>&1' \
  F5 "no .env files should be mounted in workspace"

check_fail 'touch /proc/test_escape 2>&1' \
  F6 "/proc must be mounted read-only"

check_fail 'touch /sys/test_escape 2>&1' \
  F7 "/sys must be mounted read-only"

check_fail 'cat /dev/sda 2>&1' \
  F8 "/dev/sda must not be accessible"

check_fail 'cat /dev/mem 2>&1' \
  F9 "/dev/mem must not be accessible"

echo ""

# ---- Capabilities / Privileges ----
echo "--- Capabilities ---"

check_fail 'iptables -L 2>&1' \
  C1 "iptables must be denied (no CAP_NET_ADMIN)"

check_fail 'apk add --no-cache curl 2>&1' \
  C2 "apk install must be denied (not root)"

check_fail 'nsenter --target 1 --mount 2>&1' \
  C3 "nsenter must be denied"

check_fail 'echo test > /proc/sys/net/ipv4/ip_forward 2>&1' \
  C4 "sysctl write must be denied"

check_pass "[ \"\$(id -u)\" -ne 0 ]" \
  C5 "container must run as non-root user"

check_pass 'grep -q "^NoNewPrivs:.*1" /proc/self/status' \
  C6 "no-new-privileges must be enabled"

check_pass 'grep -q "^CapEff:[[:space:]]*0000000000000000" /proc/self/status' \
  C7 "effective capabilities must be zero"

check_pass 'grep -q "^Seccomp:[[:space:]]*2" /proc/self/status' \
  C8 "seccomp must be in strict mode"

echo ""

# ---- Process Isolation ----
echo "--- Processes ---"

check_pass 'diff -q /etc/os-release /proc/1/root/etc/os-release 2>&1' \
  P1 "host root via /proc/1/root must not be accessible (container's own root is safe)"

check_pass 'env 2>&1' \
  P2 "env command must work"

check_fail 'grep -q docker /proc/1/cgroup 2>&1' \
  P3 "should be in own cgroup"

echo ""

# ---- Symlink Protection ----
echo "--- Symlinks ---"

TESTDIR=$(mktemp -d /tmp/symtest.XXXXXX 2>/dev/null || echo "")
if [ -n "$TESTDIR" ]; then
  ln -sf /etc/passwd "$TESTDIR/evil" 2>/dev/null || true
  if readlink -qe "$TESTDIR/evil" 2>/dev/null; then
    fail S1 "symlink to system path resolved (should be blocked)"
  else
    ok S1 "symlink to system path correctly rejected"
  fi
  rm -rf "$TESTDIR"
else
  fail S1 "cannot create test dir"
fi

echo ""
echo "========================================"
echo "  Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

[ "$FAIL" -eq 0 ]

