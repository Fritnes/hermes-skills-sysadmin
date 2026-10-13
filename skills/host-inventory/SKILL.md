---
name: host-inventory
description: Single source of truth for the sysadmin's list of managed hosts (servers, VMs, network devices), kept in a plain-text file and managed with one bash script. Use this skill whenever the task involves a host, server, machine, node, IP, hostname, role, environment (prod/staging/dev), lifecycle state, tag, or "my infrastructure" - including looking up how to connect to a host, listing hosts by role or environment, adding, updating or removing a host, resolving "all web servers" or "the prod databases" into concrete targets, or validating the inventory. Consult it BEFORE running any command on any host, even if the user only gives a nickname or a partial name.
---

# Host Inventory

This skill defines where the list of hosts lives, what each entry contains, and how to read and change it safely. Every other sysadmin action (health checks, patching, runbooks) starts here, because the agent must know exactly which machines exist, how to reach them, and how risky each one is. Guessing a hostname or connection detail is how commands end up on the wrong machine.

No special tooling is needed: the inventory is a text file and `scripts/hostctl.sh` is a single bash script (needs only bash, awk and ssh).

## Where the inventory lives

1. Use the path in `$HOSTCTL_INVENTORY` if set, otherwise `./hosts.conf`. If the user gives a path, use that.
2. If no file exists, offer to create one from `assets/hosts.conf.example` and ask where to save it. Do not invent hosts.
3. Treat the file as the only source of truth. If the user mentions a host that is not in it, say so and ask whether to add it. Never connect to an unlisted host.

## File format

One host per line. The basic format is 11 fields, and the skill supports two optional tail fields for lifecycle state and tags. Lines starting with `#` are comments.

```
name|address|user|port|jump|os|role|env|owner|protected|notes|state|tags
web-01|10.0.1.11|ops|22|bastion-01|debian|web|prod|platform-team|yes|nginx; maintenance window Sun 02:00-04:00|active|critical,nginx
```

| Field | Meaning |
|---|---|
| `name` | Short unique name: lowercase letters, digits, `.` `_` `-` |
| `address` | IP or DNS name used to connect |
| `user` | SSH user for this host. A least-privilege account, not root, with key authentication |
| `port` | SSH port (22 by default) |
| `jump` | Empty for a direct connection; the `name` of another inventory host (the bastion); or a literal `user@host[:port]`. Becomes `ssh -J` |
| `os` | `debian`, `redhat`, `suse`, `arch`, `freebsd`, ... |
| `role` | `web`, `db`, `cache`, `proxy`, `monitoring`, ... |
| `env` | `prod`, `staging` or `dev` |
| `owner` | Person or team to contact |
| `protected` | `yes` = every change needs explicit user confirmation. `prod` hosts default to `yes` |
| `notes` | Free text: quirks, maintenance windows, dependencies. No `|` characters |
| `state` | Optional lifecycle state: `active`, `maintenance`, `failed`, `decommissioned`, `pending` |
| `tags` | Optional comma-separated tags such as `critical`, `k3s`, `storage`, `home-lab`, `db` |

Any host without `state` is treated as `active`. Any host without `tags` is treated as untagged.

## Commands

Run these through `scripts/hostctl.sh`:

| Command | Purpose |
|---|---|
| `list [--env E] [--role R] [--state S] [--tag T]` | Table of hosts, optionally filtered |
| `names [--env E] [--role R] [--state S] [--tag T]` | Host names only, one per line |
| `show NAME` | All fields of one host |
| `add NAME ADDRESS USER OS ROLE ENV OWNER [--port N] [--jump J] [--protected yes\|no] [--state active\|maintenance\|failed\|pending\|decommissioned] [--tags TAG1,TAG2] [--notes TEXT]` | Append a host (rejects duplicate names and addresses) |
| `remove NAME --yes` | Mark as decommissioned (kept as a comment with the date). Refused while other hosts use it as their jump host |
| `validate` | Check fields, duplicates, environments, root users, jump-host loops, secrets in notes, and state/tag consistency |
| `ping NAME` | Read-only SSH reachability test (`BatchMode`, 5 s timeout), going through the jump host if one is set |

Every `add` and `remove` writes a backup (`hosts.conf.bak`) and appends a line to `hosts.log` next to the inventory.

## SSH user and jump host

- **User.** Each host has its own `user`. Never default to `root` and never guess: if the user does not say which account to use, ask. Authentication is by key only (`BatchMode` means a password prompt fails fast instead of hanging).
- **Jump host.** When a host is only reachable through a bastion, set `jump` to the bastion's inventory name so its address and user live in one place. Use a literal `user@host[:port]` only for a bastion that is not in the inventory. Whenever the agent connects to such a host, it must go through the jump host (`ssh -J`), never around it; a missing route is a problem to report, not to bypass.
- **Ask before assuming.** When adding a host, ask whether it is behind a bastion.

## How to handle requests

**Look up a host.** Match the exact name first. If the user gave a partial name or an IP, run `list` and find the matches yourself. When more than one host matches, list the candidates and ask which one; never pick silently.

**Resolve a group to targets.** For "all web servers", "the prod databases", or "all critical hosts", use `names --env ... --role ... --state ... --tag ...` and **show the resulting list to the user before any action runs**. People often mean fewer or more hosts than the agent would assume, so this confirmation is cheap insurance.

**Add a host.** Collect every required field and ask for what is missing instead of assuming (especially the SSH user, the owner, whether a jump host is needed, and the lifecycle state). Add it, run `validate`, and offer a `ping` test.

**Update a host.** There is no `update` command on purpose. Edit the line in the file with a precise replacement, show the user a before/after diff, and wait for confirmation if the host is protected. Changing `address`, `user`, `env`, `state`, or `tags` can redirect later commands to a different machine or affect the maintenance lifecycle, so say that plainly. Run `validate` afterwards and add a line to `hosts.log`.

**Remove a host.** Name the host, its environment and its owner, get explicit confirmation, then run `remove NAME --yes`. Never pass `--yes` before the user has confirmed; the flag exists so a removal cannot happen by accident.

## Handoff to operational skills

Every operational skill in this repository that inspects or acts on hosts must resolve targets through this inventory before running host commands.

- For a single host, use `show NAME` and carry forward its exact name, address, SSH user, port, jump host, environment, state, and protection status. Identify it as `NAME (ENV)` in summaries.
- For a group, use `names` with the requested environment, role, state, and/or tag filters. Show the exact resulting target list before any change; use `show NAME` for each target before connecting.
- If the inventory is unavailable, a host is missing, or a name matches more than one possible target, stop and ask the user to resolve it. Never fall back to a guessed hostname, address, or SSH account.
- Every operational skill must respect the inventory's `state` and `protected` fields. Resolving a host authorizes identification only; it does not authorize a change.

## Safety rules

- **No secrets in the inventory.** SSH keys belong in `~/.ssh` or an ssh-agent. If the user pastes a password or private key, do not write it to the file; tell them where it should go instead.
- **Always show the environment.** Write "web-02 (prod)" rather than "web-02" whenever reporting on or about to act on a host, so a mix-up is visible.
- **Read-only by default.** `list`, `names`, `show`, `validate` and `ping` never need confirmation. Any edit to the inventory shows what will change first.
- **This skill only manages the list.** For running commands, patching or health checks, resolve targets here, then follow the relevant operations skill and its confirmation rules.
- **Lifecycle matters.** A host in `maintenance` or `failed` must be treated differently from a host in `active`; never run high-risk actions without explicit confirmation.

## Example

User: "Add db-03, our new Postgres replica in prod, 10.0.2.13."

Good: ask for the SSH user, OS, owner, whether it is behind a bastion, and its lifecycle state. Then run `add db-03 10.0.2.13 dbops redhat db prod dba-team --jump bastion-01 --state active --tags critical,db --notes "PostgreSQL replica"`, run `validate`, and offer a `ping` test.

Bad: add it immediately with a guessed user of `root` or without a lifecycle state.
