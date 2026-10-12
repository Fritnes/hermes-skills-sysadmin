# Hermes Sysadmin Skills

A lightweight collection of AI agent skills for common sysadmin tasks. The goal is to keep infrastructure actions explicit, safety-first, and easy to review in plain text.

## Included skills

- `host-inventory` — maintain a single source of truth for managed hosts, SSH access, roles, owner metadata, lifecycle state, and tags.
- `linux-healthcheck` — basic Linux system checks for CPU, memory, disk, load, service health, and uptime.
- `network-diagnostics` — basic network and reachability troubleshooting for DNS, ports, routes, firewalls, and TLS.

## Repository layout

```text
Skills/
  host-inventory/
    SKILL.md
    scripts/
      hostctl.sh
    assets/
      hosts.conf.example
  linux-healthcheck/
    SKILL.md
  network-diagnostics/
    SKILL.md
README.md
```

## Quick start

1. Review the inventory format in `Skills/host-inventory/SKILL.md`.
2. Copy the example inventory and adjust it for your environment:
   ```bash
   cp Skills/host-inventory/assets/hosts.conf.example ./hosts.conf
   ```
3. List your hosts:
   ```bash
   HOSTCTL_INVENTORY=./hosts.conf bash Skills/host-inventory/scripts/hostctl.sh list
   ```
4. Add a host with lifecycle state and tags:
   ```bash
   HOSTCTL_INVENTORY=./hosts.conf bash Skills/host-inventory/scripts/hostctl.sh add web-02 10.0.1.12 ops debian web prod platform-team --state active --tags critical,nginx
   ```

## Safety principles

- always resolve the target host via the inventory first
- show the target list before performing a risky action
- prefer read-only checks before making configuration changes
- keep credentials and secrets out of the inventory file

## GitHub

This repo is designed to be easy to push to GitHub as a public or private skills repository. A typical flow is:

```bash
git init
git add .
git commit -m "Initial sysadmin skills repo"
git branch -M main
git remote add origin git@github.com:<you>/<repo>.git
git push -u origin main
```

## Notes

This repository is intentionally small and opinionated: the inventory is the entry point, and each operational skill assumes the agent has already resolved the correct host and environment before touching a system.
