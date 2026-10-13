---
name: patch-management
description: "Use for checking pending OS or package updates, security patch review, maintenance planning, staged rollouts, reboot assessment, and rollback planning. Resolve hosts through host-inventory and keep update checks read-only unless the user explicitly approves a specific change."
---

# Patch Management

Review pending operating-system updates and prepare a safe, staged maintenance plan. This skill does not install updates or reboot hosts by default.

## Assess updates

1. Clarify the target hosts, urgency, maintenance window, service constraints, and whether the request is review-only or implementation planning.
2. Resolve every host through `host-inventory`. Use exact inventory OS, environment, state, and protection fields; for groups, show the filtered target list and resolve each host before connecting. Stop on missing or ambiguous targets.
3. Identify the package manager from the host OS and installed tooling. Use its read-only update listing or security advisory command. Examples include `apt list --upgradable`, `dnf check-update`, `zypper list-updates`, and `pacman -Qu`; verify the command's meaning and exit status for that manager.
4. Record package names, installed and candidate versions, security status when available, dependency or repository issues, and whether a reboot is indicated. Do not claim a security fix based only on a package name.
5. Check service and host readiness with `linux-healthcheck` when relevant. Confirm backup coverage with `backup-restore-checks` before high-impact or difficult-to-reverse updates.

## Prepare a rollout plan

Propose a canary or staging host, batches, order, maintenance window, pre-change checks, health checks, communication needs, and stop/rollback criteria. Explain that package downgrades are not always a valid rollback; define a tested recovery method before production changes.

## Change controls

- Do not refresh repositories if that changes host state, install/remove packages, edit repositories, hold packages, or reboot without explicit approval for the exact action and targets.
- Before execution, present the package set, expected impact, target list, maintenance window, backup/recovery plan, and verification criteria. Obtain explicit confirmation; "patch everything" does not waive inventory scope or production safeguards.
- Treat reboots as a separate high-impact action requiring separate confirmation. Stop rollout on failed health checks or unexpected package changes.
- After an approved batch, verify package versions and host/service health before proposing the next batch.

## Example

For "review pending security updates for web-01", resolve `web-01`, identify its OS and package manager, list candidate updates without installing them, and return a staged plan with reboot and rollback considerations.