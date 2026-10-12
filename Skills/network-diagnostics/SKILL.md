---
name: network-diagnostics
description: Troubleshoot Linux and network reachability issues such as DNS failure, port connectivity, firewall blocks, routing problems, and service-level latency. Use this skill for "can the host reach X?", "why is port 443 failing?", or "why is the app not responding?".
---

# Network Diagnostics

Use this skill when the user reports connectivity issues, unreachable services, DNS problems, TLS errors, firewall blocks, routing issues, slow responses, or configuration mismatches.

Start by resolving the target host through the host inventory skill, then test the network path in a narrow sequence: reachability, DNS, route, port, service, and TLS.

## Quick troubleshooting flow

1. Confirm the host and scope
   - inventory lookup: `show NAME`
   - confirm exact source host and destination service

2. Reachability checks
   - `ping -c 3 HOSTNAME_OR_IP`
   - `traceroute HOSTNAME_OR_IP` or `tracepath HOSTNAME_OR_IP`
   - `ip addr show`
   - `ip route`

3. DNS checks
   - `getent hosts example.com`
   - `nslookup example.com`
   - `dig +short example.com`
   - `cat /etc/resolv.conf`

4. Port and service checks
   - `ss -tulpn | grep -E ':80|:443|:22|:3306|:5432'`
   - `nc -vz HOST 22`
   - `telnet HOST PORT` (if available)
   - `curl -Ivk https://HOST:443`

5. Firewall and policy questions
   - `iptables -S 2>/dev/null || true`
   - `nft list ruleset 2>/dev/null || true`
   - `ufw status 2>/dev/null || true`

6. Application-level validation
   - `curl -sS -D - https://HOST/ -o /dev/null`
   - `openssl s_client -connect HOST:443 -servername HOST`
   - `journalctl -u nginx -u sshd -u haproxy --since "1 hour ago"`

## Common root causes

- no route or wrong gateway
- DNS resolution failure
- closed port or firewall block
- service binds only on localhost or wrong address
- TLS mismatch or certificate issue
- upstream service down or overloaded
- MTU or packet fragmentation issues

## Safety rules

- Do not change firewall rules or routing without user approval.
- Prefer read-only checks before making configuration changes.
- If a host is marked `maintenance` or `failed`, treat network actions as higher-risk and confirm intent.
- Separate fact from hypothesis: say “port 443 is closed” before saying “the firewall is blocking it.”

## Example

User: “web-01 cannot reach the database on port 5432.”

Good: run `ss -tulpn`, `nc -vz db-01 5432`, `ping -c 3 db-01`, and `getent hosts db-01` to isolate whether the issue is DNS, routing, firewall, or service binding.

Bad: immediately assume the database is down without proving the path, port, and service state.
