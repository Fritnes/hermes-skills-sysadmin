---
name: fail2ban-audit
description: "Read-only audit of fail2ban on one or more remote Linux hosts over SSH: service state, jails, ban settings, banned IPs, and firewall enforcement. Always resolve managed targets through host-inventory first. Use for requests to audit, check, review, verify, or troubleshoot fail2ban, banned IPs, jails, nftables or iptables enforcement, or compare fail2ban across servers. For installation or configuration changes, ask for explicit confirmation."
---

# fail2ban audit

Audits fail2ban on remote hosts and returns a verdict (PASS / WARN / FAIL) per check, not a raw dump. **The audit is strictly read-only.** Never change config, restart services, or unban IPs as part of it; any fix needs explicit user confirmation first.

## Inventory-first target resolution

Every audit target must be resolved through the `host-inventory` skill before connecting. Do not treat a user-provided hostname, address, or `user@host` string as a substitute for inventory resolution.

- For one host, use `host-inventory show NAME`. Carry forward its exact name, address, SSH user, port, jump host, environment, state, and protection status; report it as `NAME (ENV)`.
- For multiple hosts, use `host-inventory names` with the requested environment, role, state, or tag filters. Show the resulting target list, then use `show NAME` for each before connecting.
- If the inventory is unavailable, a target is missing or ambiguous, or its connection details are incomplete, stop and ask the user. Never guess or bypass an inventory jump host.
- Build the SSH connection from the resolved inventory fields. If `jump` names another inventory host, resolve that host too and use its inventory SSH user, address, and port as the `-J` destination.

## Prerequisites

- Non-interactive SSH access matching the resolved inventory user, address, port, and jump-host route (key or agent auth).
- Root login, or passwordless sudo (`sudo -n`). Without it the script reports a limited audit and most checks will fail.

## How to run

The audit logic lives in `scripts/audit.sh` and is piped to the remote shell. This avoids all quoting problems from embedding a script inside `ssh host '...'`.

Single host, direct connection (replace placeholders with values from `host-inventory show NAME`):

```bash
ssh -o BatchMode=yes -o ConnectTimeout=10 -p PORT USER@ADDRESS 'bash -s' < scripts/audit.sh
```

If the inventory specifies a jump host, resolve its connection fields through `host-inventory` and include it with `-J`:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=10 -p PORT -J JUMP_USER@JUMP_ADDRESS:JUMP_PORT USER@ADDRESS 'bash -s' < scripts/audit.sh
```

Several hosts in parallel, with a summary table and full reports saved per host:

```bash
scripts/audit_hosts.sh HOST_ALIAS_1 HOST_ALIAS_2
```

The multi-host helper accepts SSH destination tokens, not inventory records or per-host `-p`/`-J` options. Use it only when each SSH config alias maps to the inventory's user, address, port, and jump-host route. Otherwise run the single-host command per resolved target with explicit SSH options. `BatchMode=yes` makes SSH fail immediately instead of hanging on a password prompt. If SSH itself fails, report that as the finding (unreachable / auth failed) and stop for that host.

Paths are relative to this skill's folder.

## What the script checks

| Area | Checks |
|---|---|
| Service | active, enabled at boot, daemon answers `ping`, version |
| Jails | at least one active; an ssh jail exists if sshd listens on :22; recidive present (info) |
| Per-jail settings | `maxretry`, `findtime`, `bantime`, `ignoreip`, actions; flags permanent bans (`-1`), very high `maxretry`, very short times, empty `ignoreip` |
| Enforcement | **fail2ban's "Currently banned" count vs. elements actually in the nft set / iptables chain** (FAIL if fail2ban has bans but the firewall holds none) |
| Admin safety | your SSH client IP is not banned; whether it is covered by `ignoreip` |
| Logs | ERROR/CRITICAL in the last 24h (journal, falling back to `/var/log/fail2ban.log`) |

Output lines start with `PASS:`, `WARN:`, `FAIL:` or `INFO:`, ending with `SUMMARY pass=N warn=N fail=N`.

## Reporting results

Give the user a short report, not the raw output:

1. **Per-host verdict**: one line (healthy / warnings / failing) with the SUMMARY counts.
2. **Findings**, ordered FAIL then WARN, each with the jail/host and a one-line suggested fix.
3. **Notable facts**: banned counts, active jails, backend in use. Include banned IPs only if the user asked; get them with `fail2ban-client status <jail>`.
4. For several hosts, a table of hosts x verdict, then the details of any host that is not clean.

Do not claim a check passed if the script could not run it (limited audit, missing tool). Say it was not verified.

## Interpreting results

For the meaning of a FAIL/WARN and how to resolve it, read `references/common-issues.md`.
For backend-specific inspection commands (nftables, iptables, firewalld, ban action to backend mapping), read `references/backends.md`.
Read them only when needed: when a finding needs diagnosis, or the user asks to dig into a backend.

## Gotchas

- `fail2ban-client status --jails` is **not** a valid command ("the jail '--jails' does not exist"). Jail names come from the `Jail list:` line of plain `status`; the script does this.
- Non-interactive SSH has a reduced PATH, so `nft`, `iptables` and `firewall-cmd` (in `/usr/sbin`) look missing unless PATH is extended. The script handles this; do it too for any follow-up commands.
- `fail2ban-client banned` returns a Python-dict style string; use per-jail `status` instead.
- Don't embed inline `python3 -c` or nested quotes in an `ssh host '...'` one-liner. For ad-hoc follow-ups, pipe a heredoc: `ssh host 'bash -s' <<'EOF' ... EOF`.
- Small count differences (1-2) between fail2ban and the firewall are normal (timing, expiry), so the script only warns above that. IPv6 bans can also skew counts.
- If the firewall cross-check says "no f2b nft set or iptables chain found" while bans exist, the host may use firewalld, ipset, or a custom action. Verify manually with `references/backends.md`.

## Follow-up actions (need user confirmation)

Only after the user approves a specific change:

- Edit `/etc/fail2ban/jail.local` (never `jail.conf`), using `sudo tee -a` or an editor so the write runs as root.
- Validate before reloading: `sudo fail2ban-client -t`, then `sudo systemctl reload fail2ban` (restart if reload is insufficient).
- Re-run the audit afterwards to confirm the finding is cleared.
