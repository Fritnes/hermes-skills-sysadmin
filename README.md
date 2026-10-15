# Hermes Sysadmin Skills

Hermes Agent skills for host inventory, Linux health checks, network diagnostics, and security operations. The workflows prioritize explicit targets, read-only checks, and confirmation before risky changes.

## Repository structure

```text
skills/
├── host-inventory/
│   ├── SKILL.md
│   ├── assets/
│   │   └── hosts.conf.example
│   └── scripts/
│       └── hostctl.sh
├── host-inspect/
│   ├── SKILL.md
│   ├── references/
│   │   ├── containers.md
│   │   └── mdraid.md
│   └── scripts/
│       ├── inspect.sh
│       └── run.sh
├── linux-healthcheck/
│   └── SKILL.md
├── network-diagnostics/
│   └── SKILL.md
├── incident-triage/
│   └── SKILL.md
├── service-operations/
│   └── SKILL.md
├── backup-restore-checks/
│   └── SKILL.md
├── patch-management/
│   └── SKILL.md
├── storage-diagnostics/
│   └── SKILL.md
├── security-audit/
│   └── SKILL.md
└── fail2ban-audit/
    └── SKILL.md
```

Each folder in `skills/` contains a `SKILL.md` with the skill instructions. The host inventory skill also includes an example inventory and a Bash management script.

## Available skills

| Skill | Purpose | Example request |
|---|---|---|
| `host-inventory` | Find, validate, and manage hosts, roles, environments, lifecycle states, and tags. | "List the production web hosts" |
| `host-inspect` | Read-only inspection of host health, services, logs, network, security, containers, and RAID, using inventory-resolved targets. | "Inspect web-01 and report any issues" |
| `linux-healthcheck` | Gather read-only CPU, memory, disk, service, and uptime signals. | "Check whether web-01 is healthy" |
| `network-diagnostics` | Troubleshoot DNS, routes, ports, firewalls, reachability, and TLS. | "Why can't web-01 reach db-01 on port 5432?" |
| `incident-triage` | Correlate inventory, health, service, and network evidence without changing systems. | "Triage why web-01 is responding slowly" |
| `service-operations` | Inspect systemd units and guide approved service state changes. | "Check nginx on web-01 and explain a safe reload" |
| `backup-restore-checks` | Review backup coverage and freshness, then plan a safe restore test. | "Check whether db-01 has a recent restorable backup" |
| `patch-management` | Assess pending updates and prepare a staged, reversible maintenance plan. | "Review pending security updates for web-01" |
| `storage-diagnostics` | Inspect filesystem, inode, mount, SMART, and LVM capacity signals. | "Find what is filling /var on web-01" |
| `security-audit` | Run read-only SSH, exposure, update, permissions, and firewall checks. | "Audit SSH and listening ports on web-01" |
| `fail2ban-audit` | Audit Fail2Ban service, jails, bans, and firewall enforcement without changing the host. | "Check whether Fail2Ban is banning correctly on web-01" |

## Install

Copy all skills into your Hermes skill directory:

```bash
mkdir -p ~/.hermes/skills
cp -r skills/* ~/.hermes/skills/
```

To install only selected skills, name their folders explicitly:

```bash
cp -r skills/host-inventory skills/host-inspect skills/linux-healthcheck ~/.hermes/skills/
```

## Using a skill

Ask Hermes normally and it may select a relevant skill automatically. To request one explicitly, start your message with its slash command:

```text
/host-inventory list production web hosts
/host-inspect inspect web-01 and report any issues
/linux-healthcheck check web-01
/network-diagnostics troubleshoot web-01 reaching db-01 on port 5432
/incident-triage triage why web-01 is responding slowly
/service-operations inspect nginx on web-01
/backup-restore-checks check db-01 backup freshness and plan a restore test
/patch-management review pending updates for web-01
/storage-diagnostics inspect disk and inode usage on web-01
/security-audit review SSH and exposed ports on web-01
/fail2ban-audit audit Fail2Ban on web-01
```

## Host inventory setup

Create a local inventory from the example, then replace its sample entries with your own:

```bash
cp skills/host-inventory/assets/hosts.conf.example ./hosts.conf
HOSTCTL_INVENTORY=./hosts.conf bash skills/host-inventory/scripts/hostctl.sh validate
HOSTCTL_INVENTORY=./hosts.conf bash skills/host-inventory/scripts/hostctl.sh list
```

The inventory is the source of truth for managed hosts. Set `HOSTCTL_INVENTORY` to use a different path; otherwise the script uses `./hosts.conf`. The example entries are documentation only and must be replaced before use.

## Safety principles

- Resolve the host and environment through the inventory before any remote action.
- Show the resolved target list before acting on a group of hosts.
- Prefer read-only checks; get approval before risky changes, such as modifying routes or firewall rules.
- Keep passwords, tokens, and private keys out of inventory files.

## Adding a skill

1. Create a folder under `skills/` using the skill name.
2. Add a `SKILL.md` with `name` and `description` frontmatter.
3. Add supporting scripts or assets in that folder as needed.
4. Add the skill to the table in this README.
