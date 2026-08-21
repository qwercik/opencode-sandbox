# Sandbox Security Test Report

## 1. Basic Information

| Parameter | Value |
|----------|-------|
| System | Docker container (Alpine Linux) |
| Kernel | 6.17.0-23-generic (Ubuntu) |
| User | uid=1000 (unknown in /etc/passwd) |
| Container ID | fb671623e0fd |
| Hostname | fb671623e0fd |
| ASLR | Enabled (2) |

## 2. Process Isolation

| Test | Result |
|------|--------|
| Host process visibility | ❌ Only own processes visible |
| /proc/1 (opencode) | ✅ Visible, but env vars are container-only |
| Other container processes | ❌ Not visible |

## 3. Filesystem Isolation

| Test | Result |
|------|--------|
| Write to `/` | ❌ Denied |
| Write to `/etc/` | ❌ Denied |
| Write to `/home/` | ❌ Denied |
| Write to `/sys/` | ❌ Read-only |
| Write to `/proc/sys/` | ❌ Read-only |
| Write to `/project/` | ✅ YES |
| Write to `/tmp/` | ✅ YES |
| Access to `/root/` | ❌ Denied |
| Dangerous dev nodes (mem, sda) | ❌ Not accessible |

## 4. Capabilities

| Test | Result |
|------|--------|
| CapEff | 0000000000000000 — ZERO |
| CapPrm | 0000000000000000 — ZERO |
| CapBnd | 00000000a80425fb |
| User namespace | ❌ Not used |

## 5. Seccomp and AppArmor

| Test | Result |
|------|--------|
| Seccomp | Mode 2 (strict), 1 filter |
| AppArmor | `docker-default (enforce)` |
| SELinux | ❌ Not available |
| dmesg | ❌ Blocked |

## 6. Network

| Test | Result |
|------|--------|
| Interfaces | eth0@if356 + lo |
| Container IP | 172.17.0.2/16 |
| Host (gateway) | 172.17.0.1 (host.docker.internal) |
| Docker socket | ❌ Not mounted |
| Listening ports | ❌ None |
| DNS | 1.1.1.1, 8.8.8.8 |

### 6.1 Host Access (172.17.0.1)

| Test | Result |
|------|--------|
| Ping | ✅ Reachable (0.231ms) |
| Port 22 | ❌ Closed |
| Port 80 | ❌ Closed |
| Port 443 | ❌ Closed |
| Port 7777 | ❌ Closed (Connection refused) |

**Conclusion:** Host is reachable, but no ports are open. If the user runs a service on the host (e.g. a web server on port 7777), the agent could connect to it via 172.17.0.1:7777 or host.docker.internal:7777.

### 6.2 Local Network (LAN) Access

| Test | Result |
|------|--------|
| 192.168.1.1 | ✅ Reachable (2.970ms) |
| 10.0.0.1 | ❌ Unreachable |
| 172.16.0.1 | ❌ Unreachable |
| ARP cache | Host only (172.17.0.1) |

**Conclusion:** The container has routing through the host, so the agent could potentially scan the local LAN (192.168.x.x) and attempt to connect to devices (router, NAS, printers, IoT, other computers).

## 7. Escape Vectors

| Vector | Status |
|--------|--------|
| Cgroup release_agent | ❌ Closed (cgroup v2, no notify_on_release) |
| Docker socket | ❌ Not mounted |
| Mount | ❌ No privileges |
| /sys write | ❌ Read-only |
| /proc/sys write | ❌ Read-only |
| Kernel modules | ❌ Read-only |
| Shared memory (/dev/shm) | Empty |

## 8. Summary and Recommendations

The sandbox is **very tight** — most attack vectors are closed. The only real concern is **LAN access**.

### Recommended iptables rules (whitelist instead of total block)

If you need MCP access to another container:

```bash
# Block LAN access
iptables -A FORWARD -i docker0 -s 172.17.0.0/16 -d 192.168.0.0/16 -j DROP
iptables -A FORWARD -i docker0 -s 172.17.0.0/16 -d 10.0.0.0/8 -j DROP
iptables -A FORWARD -i docker0 -s 172.17.0.0/16 -d 172.16.0.0/12 -j DROP

# Block host access (optional, if not needed)
iptables -A FORWARD -i docker0 -s 172.17.0.0/16 -d 172.17.0.1 -j DROP

# Allow a specific MCP container (find its IP)
iptables -I FORWARD -i docker0 -s 172.17.0.0/16 -d 172.17.x.x -j ACCEPT
```

### Alternative — dedicated Docker network

```bash
docker network create mcp-net
docker network connect mcp-net container-mcp
docker network connect mcp-net container-agent
```

This way containers see each other on the same network, while LAN/host access can be controlled separately.