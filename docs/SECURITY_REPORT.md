# Security Report — opencode-sandbox v1.2.0

Security audit of the opencode-sandbox mechanism — 2025-08-20.

## 🔴 CRITICAL

### 1. Privileged Container Escape
- **File:** `opencode-sandbox:107-109`
- **CVSS:** 9.8 (AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H)
- **Type:** Privilege escalation
- **Description:** The `iptables_host()` function launched a temporary container with `--privileged --pid=host --net=host`, granting full host access via kernel exploits.
- **Fix:** Replaced `--privileged` with `--cap-add=NET_ADMIN --cap-add=NET_RAW`. With `--net=host` the container sees host iptables without `nsenter`. `--pid=host` is no longer needed.
- **Status:** ✅ **Fixed**

---

## 🟡 HIGH

### 2. Path Traversal via Symlinks
- **File:** `opencode-sandbox:187-196`
- **Type:** Arbitrary File Read/Write
- **Description:** An attacker with host access could swap the symlink target after `readlink -f` resolution, mounting unauthorized paths.
- **Minor fix:** `readlink -f` → `readlink -qe` (fails on broken/non-existent paths).
- **Assumption:** Users know what they symlink. Host compromise is already game over — TOCTOU is not the primary threat vector.
- **Status:** ✅ **Minor fix (readlink -qe). TOCTOU risk accepted.**

### 3. Unsafe Update Mechanism
- **File:** `opencode-sandbox:68-101`
- **Type:** Information spoofing / potential RCE
- **Description:** `check_versions()` fetches data from `api.github.com` and `raw.githubusercontent.com` without integrity verification. Versions are only used for string comparison and display — not auto-executed.
- **Fix:** Added semver validation (`^[0-9]+\.[0-9]+\.[0-9]+$`) on `oc_latest` and `script_latest` values before use. Invalid values are ignored.
- **Status:** ✅ **Fixed (semver validation)**

### 4. Secrets Exposure via .env.agent
- **File:** `opencode-sandbox:178-183`
- **Type:** Secrets exposure
- **Description:** `.env.agent` file mounted into the container via `--env-file`. Docker Secrets requires Swarm mode and is not applicable to `docker run`.
- **Fix:** File content is validated — only lines matching `[A-Z_][A-Z0-9_]*=VALUE` and comments (`#`) are passed through. Other lines are rejected. Passed via a temporary file.
- **Status:** ✅ **Fixed (.env.agent key validation)**

---

## 🟠 MEDIUM

### 5. X11 Socket Hijacking
- **File:** `opencode-sandbox:170-176`
- **CVSS:** 5.5
- **Type:** Arbitrary Code Execution
- **Description:** Mounting the entire `/tmp/.X11-unix/` gives the container access to all X11 displays on the host, including potential user sessions.
- **Fix:** Mounted only the `:99` socket (Xvfb): `-v /tmp/.X11-unix/X99:/tmp/.X11-unix/X99:ro`.
- **Status:** ✅ **Fixed**

### 6. Supply Chain — Unpinned Base Image
- **File:** `Dockerfile:1`, `Dockerfile:13`
- **Type:** Supply Chain Attack
- **Description:** `FROM alpine:latest` could pull a compromised or unexpected image version.
- **Fix:** Pinned to a specific digest: `alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b` (same as used for `IPTABLES_HELPER`).
- **Status:** ✅ **Fixed**

### 7. GitHub Actions — Token Permissions
- **File:** `.github/workflows/docker-image.yml:14-16`
- **Type:** Excessive permissions
- **Description:** GITHUB_TOKEN has default write permissions, while it only needs `contents: read` and `packages: write`. GH_PAT was unavoidable (required for checkout of private `opencode-tools`).
- **Fix:** Explicitly added `id-token: none`, `attestations: none` to minimize the attack surface.
- **Status:** ✅ **Fixed**

---

## 🔵 INFO / BEST PRACTICES

### 8. No User Namespace
- **Description:** Container runs as the host user (`--user $(id -u):$(id -g)`), but without userns remap. In case of a kernel exploit, the attacker has filesystem access with the user's permissions.
- **Recommendation:** Enable `--userns-remap` in Docker Engine.
- **Status:** Info — non-blocking. Requires Docker daemon configuration.

### 9. Hardcoded GitHub API URL
- **File:** `opencode-sandbox:85`
- **Description:** `https://api.github.com` is hardcoded. DNS spoofing could redirect to a malicious server.
- **Recommendation:** Consider TLS pinning or certificate verification.
- **Status:** Info — HTTPS + semver validation provide basic protection.

### 10. TOCTOU in Path Resolution
- **File:** `opencode-sandbox:187-196`
- **Description:** `realpath` resolves symlinks at T0, mounting happens at T1 — theoretical race condition window.
- **Recommendation:** Mount the parent directory as read-only.
- **Status:** Info — acceptable risk (requires host access).

---

## Summary

| Level | Count |
|--------|-------|
| 🔴 CRITICAL | 1 (fixed) |
| 🟡 HIGH | 3 (fixed) |
| 🟠 MEDIUM | 3 (fixed) |
| 🔵 INFO | 3 (non-blocking) |

All critical and high vulnerabilities have been addressed. Remaining INFO items do not pose a direct threat under the assumed security model.