---
name: host-inspect
description: Read-only inspection and diagnosis of Linux hosts, with managed targets resolved through host-inventory first. Supports local shells and explicit transports such as SSH, bastion/jump hosts, docker/podman exec, kubectl exec, cloud agents, LXC/Incus, and serial consoles. Covers system health (CPU, RAM, load, disk), services and logs, network/ports/firewall, security posture (SSH config, users, updates), containers (Docker/Podman), and software RAID (mdraid). Use this skill whenever the user wants to check, audit, triage, health-check, troubleshoot, or "look at" a server, VPS, VM, container, workstation, or "this machine", asks why a host is slow/full/down/degraded, mentions a hostname or IP to investigate, or asks for a system report - even if they don't say "inspect". Never modifies the host; proposes fixes as commands for the human to run.
---

# Host Inspect

Inspect a Linux host - **local or remote, over any connection type** - **read-only**, find problems, and **suggest** fixes. The agent never applies fixes itself.

## Inventory-first target resolution

Resolve every host through the `host-inventory` skill before running inspection commands. A hostname, IP, SSH destination, container name, or cloud resource supplied by the user is not a substitute for inventory resolution.

- For one host, use `host-inventory show NAME`; carry forward its exact address, SSH user, port, jump host, environment, state, and protection status. Report it as `NAME (ENV)`.
- For a group, use the inventory's filtered `names` lookup, show the exact target list, then use `show NAME` for each host before connecting.
- If the inventory or target is missing, ambiguous, or lacks the needed connection details, stop and ask the user to resolve it. Never guess a host, account, transport, or route.
- Resolve an inventory-named jump host too, and use its recorded user, address, and port. Never bypass the recorded jump route. Honor lifecycle and protection fields; inventory resolution identifies the target but does not authorize changes.
- For local inspection, resolve the local machine through the inventory and confirm the shell is actually on that machine; a sandbox or container may expose a different host view. For nested targets such as containers or pods, resolve the parent host and confirm the exact nested target before executing there.
- Use a non-SSH transport only when the inventory and user-provided details identify the exact resource and route. If those details are unavailable, stop rather than falling back to an arbitrary transport.

## Hard rules (non-negotiable)

1. **Read-only.** Do not run anything that changes state on the host: no `rm`, `mv`, `kill`, `systemctl restart/stop/enable`, `apt/dnf install|upgrade`, `mdadm --add/--fail/--remove/--stop/--assemble`, `docker rm/stop/restart/prune`, `iptables/ufw/nft` rule changes, `sed -i`, redirects into files, `crontab -e`, `chmod/chown`, `reboot`.
2. **Suggest, don't execute.** Fixes go in the report as commands in code blocks, each with the risk and a verification step. The human runs them.
3. **No secrets in output.** If a command would print credentials (env of containers, `/etc/shadow` contents, private keys, tokens in config), don't print it. The bundled script only checks for *empty* passwords, never prints hashes. If you see a secret anyway, redact it in the report and flag it as a finding.
4. **Don't guess the target.** Confirm which host (local, or hostname/IP/container/pod, plus any jump host) if not clear. Never inspect hosts the user didn't name. "This machine" = local.
5. **No interactive auth.** Use non-interactive transports (`ssh -o BatchMode=yes`). If auth fails, report it and ask the user - don't try other credentials. Use `sudo -n` only (never prompt, never pass passwords).

## Workflow

### 1. Establish where and how
Resolve the target through `host-inventory` first, then decide how to reach that exact target. Ask the user only for missing or ambiguous details.

| Target | Transport command (the part after `--` in `run.sh`) |
|---|---|
| This machine | *(none - runs locally)* |
| SSH host | `ssh -o BatchMode=yes -o ConnectTimeout=10 -p PORT USER@ADDRESS` using inventory values |
| SSH via bastion | `ssh -J JUMP_USER@JUMP_ADDRESS:JUMP_PORT -p PORT USER@ADDRESS` using both resolved inventory records |
| Custom key/port | `ssh -i CONFIRMED_KEY_PATH -p PORT USER@ADDRESS`; never create keys or change SSH configuration |
| Docker / Podman container | `docker exec -i NAME` / `podman exec -i NAME` |
| Kubernetes pod | `kubectl exec -i POD -n NS --` |
| Existing Kubernetes pod | `kubectl exec -i POD -n NS --` (only the inventory-resolved pod and namespace) |
| LXC / Incus | `incus exec NAME --` / `lxc exec NAME --` |
| Host view from a privileged container | `nsenter -t 1 -m -u -n -p` |
| libvirt guest | `virsh qemu-agent-command` or SSH into the guest |
| AWS SSM / GCP / Azure | see "Cloud agents" below |
| Serial/console, anything else | any command that yields a shell and reads a script from stdin; otherwise paste script contents and run commands by hand |

Rules for any transport: it must be non-interactive, and the agent must not change how access works (no key creation, no config edits).

**Local caveats.** Confirm the shell really is the user's machine: a sandboxed or containerized agent environment would inspect the sandbox, not their host (check `systemd-detect-virt`, `hostname`). Inside a container you only see the container's view (no host RAID/firewall/journal) - say so in the report. Supported: Linux (including WSL). macOS/BSD/Windows are out of scope for the script; use ad-hoc native read-only commands (`diskutil list`, `vm_stat`, `netstat`, PowerShell `Get-*`) and the same report format.

Check what privilege is available: `<transport> sudo -n true && echo SUDO_OK` (or `id -u` = 0). Many checks (firewall rules, mdadm detail, SMART, other users' logs, container inspect) need root. If not available, say which checks were skipped rather than silently omitting them.

**Cloud agents.** Where no SSH exists, use only a preconfigured agent and a non-interactive command channel that targets the inventory-resolved resource. Do not create keys, install agents or extensions, or change cloud metadata/access configuration to enable inspection. If the available method requires those changes, stop and ask. Send only this read-only script as the command payload, and poll for output instead of re-running.

### 2. Collect with the bundled scripts
`scripts/inspect.sh` is a read-only collector (no writes, 20 s timeout per command, output capped, tolerant of missing tools). `scripts/run.sh` pipes it through whatever transport you give it, so nothing is installed on the target:

```bash
# resolved local inventory host, all sections, with sudo -n if permitted
scripts/run.sh --sudo > /tmp/inspect.txt 2>&1

# remote over SSH; use the user, address, port, and jump route resolved from inventory
scripts/run.sh --sudo -- ssh -o BatchMode=yes -p PORT USER@ADDRESS > /tmp/inspect-host.txt 2>&1

# a container, only some sections
scripts/run.sh --sections resources,services,network -- docker exec -i web

# no wrapper: the raw form works with any shell transport
<transport> 'bash -s -- --sudo mdraid,disk' < scripts/inspect.sh
```

Sections: `system, resources, disk, mdraid, services, logs, network, firewall, security, containers, updates`.

Match the scope to the request. "Why is it slow?" -> `resources,disk,services,logs,containers`. "Is it secure?" -> `security,network,firewall,updates`. "Full report" -> all. Read the output file yourself; it can be long.

### 3. Drill down with ad-hoc read-only commands
The script is a first pass. When something looks off, follow up with targeted commands (see `references/` for what to look at):

- Disk full → `du -xh --max-depth=1 / 2>/dev/null | sort -h | tail`, `lsof +L1` (deleted-but-open files)
- Service failing → `systemctl status <unit> --no-pager`, `journalctl -u <unit> -n 100 --no-pager`
- RAID degraded → see `references/mdraid.md`
- Container problems → see `references/containers.md`
- Network → `ss -tnp state established`, `ip -s link`, `curl -sS -o /dev/null -w '%{http_code}\n' http://localhost:PORT/` for a local health probe

Run ad-hoc commands through the same transport. Before each one, ask: could this change anything? If unsure, don't run it.

### 4. Report
Use this structure. Keep it scannable; lead with what matters.

```
# Host report: <hostname> (<OS>, kernel <ver>, up <time>)
Inspected <timestamp> via <local/ssh/docker exec/ssm...>; sudo: yes/no; skipped checks: <list>

## Verdict
<one or two sentences: healthy / degraded / critical, and the top issue>

## Findings
| Severity | Area | Finding | Evidence |
|---|---|---|---|
| CRITICAL | mdraid | md0 degraded [U_], sdb failed | /proc/mdstat |
| WARNING  | disk   | / at 91%, /var/log 14G | df -h |
| INFO     | ...

## Suggested fixes (not applied)
1. <finding> - what/why
   ```bash
   <command(s)>
   ```
   Risk: <what could go wrong>. Verify: <command + expected result>.

## Healthy / checked OK
<short list so the user knows what was covered>
```

Severity guide: **CRITICAL** = data loss risk or outage now (degraded/failed RAID, read-only fs, disk 95%+, SMART failing, OOM-killing key services, root SSH with passwords on public IP and active brute force). **WARNING** = will become critical or is a clear weakness (disk 80-95%, pending security updates, reboot required, exited/restarting containers, failed units, exposed unexpected ports, no firewall). **INFO** = notable but fine.

State uncertainty honestly: if evidence is thin ("one failed unit, logs rotated"), say what's unknown and what command would settle it.

## Interpretation cheat-sheet

| Signal | Meaning / next step |
|---|---|
| load avg > nproc sustained | CPU or IO bound; compare `vmstat` `us/sy` vs `wa`; check PSI in `/proc/pressure` |
| `MemAvailable` low + swap used heavily | memory pressure; check top RSS and `dmesg` OOM lines |
| `df -i` 100% with free space | inode exhaustion; find dir with huge file counts |
| `/` or data fs mounted `ro` | fs errors forced remount; check `dmesg`; suggest fsck during maintenance, **never** run it live |
| `systemctl --failed` non-empty | `systemctl status` + `journalctl -u` for each |
| listening on `0.0.0.0`/`::` unexpectedly (DB, redis, docker API 2375) | exposure risk; compare with firewall rules |
| sshd `PasswordAuthentication yes` / `PermitRootLogin yes` | suggest key-only, `PermitRootLogin prohibit-password`; warn to keep a second session open when changing |
| many "Failed password" in last 24h | brute force; suggest fail2ban/rate limits, key-only auth |
| docker published port bypassing ufw | Docker edits iptables directly; verify with `iptables -S DOCKER-USER` |

For detailed guidance read:
- `references/mdraid.md` - interpreting `/proc/mdstat`, `mdadm --detail`, failure/rebuild/mismatch situations and safe remediation advice
- `references/containers.md` - Docker/Podman triage and hardening checks

## Safety notes for suggested fixes
- Always recommend a backup/snapshot before risky changes, and for RAID say "confirm backups first; a rebuild stresses the surviving disks."
- For SSH/firewall changes, advise keeping an existing session open and testing from a second one before closing.
- Prefer reversible, minimal changes. State the rollback.
- Never suggest `mdadm --create`, `--zero-superblock`, or `fsck`/`xfs_repair` on a mounted device as a first step.
