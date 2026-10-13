---
name: linux-healthcheck
description: Basic Linux host health checks for disk, memory, CPU, load, services, process pressure, and uptime. Use this skill before patching, troubleshooting a degraded server, or deciding whether a machine is safe to act on. Always resolve the target through host-inventory first, then gather read-only readiness signals.
---

# Linux Health Check

Use this skill when the user asks for a quick health pass on a Linux machine or wants to know whether a server is overloaded, low on disk, or unhealthy before performing change operations.

This skill depends on `host-inventory` and is intentionally read-only and fact-based: resolve the target there first, gather the signals, then explain what they mean.

## Required operating assumptions

- For a single host, use host-inventory `show NAME`; for a group, use its `names` filters and resolve each returned host with `show NAME` before connecting.
- Carry forward the exact inventory name, address, SSH user, port, jump host, environment, state, and protection status. Report each target as `NAME (ENV)`.
- If the inventory is unavailable or the target is missing or ambiguous, stop and ask the user to resolve it. Never guess a host or connection detail.
- Prefer a single short command sequence over long interactive diagnostics.
- Use `sudo` only when the user explicitly allows privilege escalation or when the command requires it.
- Do not guess; report the exact command and the exact meaning of the output.

## Basic checks to run

Run the checks in this order:

1. Uptime and load
   - `uptime`
   - `uname -a`
   - `cat /proc/loadavg`

2. CPU and process pressure
   - `lscpu`
   - `mpstat 1 3` (if available)
   - `ps -eo pid,comm,%cpu,%mem,rss --sort=-%cpu | head`
   - `ps -eo pid,comm,%cpu,%mem,rss --sort=-%mem | head`

3. Memory
   - `free -h`
   - `cat /proc/meminfo | egrep 'MemTotal|MemAvailable|MemFree|SwapTotal|SwapFree'`

4. Disk
   - `df -h`
   - `df -ih`
   - `lsblk -f`
   - `du -sh /var /tmp /home 2>/dev/null`

5. Filesystem health
   - `mount | column -t`
   - `journalctl -p err --since "1 hour ago"` (if systemd)
   - `dmesg -T | tail -n 50`

6. Services and system state
   - `systemctl --failed --all`
   - `systemctl list-units --state=failed --no-pager`
   - `systemctl is-active sshd nginx mysql postgresql 2>/dev/null || true`

7. Network and connection stability (if the issue may be external)
   - `ss -tulpn | head -n 50`
   - `ss -s`

## How to interpret the results

- CPU
  - sustained load above the number of logical CPUs often means the machine is busy or stuck under pressure
  - a process list dominated by one or two consumers usually points to a service issue or runaway job

- Memory
  - very low free memory or heavy swap use suggests pressure and possible slowdown
  - high memory consumption without matching workload may indicate a leak or a misconfigured service

- Disk
  - more than 80% usage on root or data partitions is a warning sign
  - inode exhaustion or full `/tmp` or `/var/log` often causes application failures

- Load
  - a machine can look healthy while still under load; compare load averages to logical CPU count

- Systemd failures
  - failed units often explain a service outage better than raw CPU numbers

## Safety rules

- Treat the result as a readiness summary, not a fix.
- Never restart or kill processes without confirming the service owner and impact.
- If a host is in `maintenance` or `failed` state, do not run broad remediation without explicit approval.
- Write down whether the machine is healthy, degraded, or critically unhealthy before advising the next action.

## Example

User: "Check if web-01 is healthy."

Good: gather `uptime`, `free -h`, `df -h`, and `systemctl --failed --all`, then report a concise summary such as: the server is healthy, has 1.8 GiB free memory, 70% disk usage, and no failed services.

Bad: immediately restarting services without checking load, memory, and disk first.
