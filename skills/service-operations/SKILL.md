---
name: service-operations
description: "Use for systemd service operations: inspect unit status, logs, dependencies, startup configuration, and requests to start, stop, restart, reload, enable, or disable a service. Resolve the host through host-inventory; require explicit confirmation before changing service state."
---

# Service Operations

Inspect and manage systemd services on inventory-managed Linux hosts. Inspection is read-only. Every service-state or unit-configuration change requires explicit, action-specific user confirmation.

## Resolve and inspect

1. Resolve the host with `host-inventory show NAME`. For a group, use its filtered `names` lookup, present the exact targets, and resolve each host before connecting. Use the inventory address, SSH user, port, and jump host; identify the host as `NAME (ENV)`.
2. If the inventory is unavailable or the host is not found, stop and ask; never connect using an unverified host or address. Confirm the exact unit name and requested operation. If the unit or host is ambiguous, stop and ask.
3. Inspect only the relevant signals:

   ```bash
   systemctl status UNIT --no-pager
   systemctl show UNIT -p LoadState,ActiveState,SubState,UnitFileState,FragmentPath,After,Requires,Wants
   systemctl list-dependencies UNIT --no-pager
   journalctl -u UNIT --since "1 hour ago" --no-pager -n 100
   ```

   Adjust the log window to the incident. Unit files and logs can contain sensitive values; do not reproduce credentials or unrelated log data.

## Before a change

Do not change state by default. Before a restart, reload, start, stop, enable, disable, mask, unmask, daemon reload, or unit-file edit:

- explain the observed state and proposed exact command
- state the exact `NAME (ENV)`, unit, operation, expected impact, and rollback or recovery option
- obtain explicit user confirmation for that operation; a general request to "fix it" is not confirmation
- honor `protected=yes` and production safeguards from the inventory

Do not combine service changes across hosts into an unreviewed loop. A reboot, package change, or firewall change is outside this skill and requires its own approval and workflow.

## After approval

Run only the confirmed operation on the confirmed target. Verify the resulting `ActiveState` and `SubState`, inspect a short post-change log window, and report the exact command and result. If the action fails or causes unexpected impact, stop; do not retry or broaden the change without approval.

## Example

For "reload nginx on web-01", resolve `web-01`, inspect the unit and recent logs, explain the expected effect of `systemctl reload nginx`, and wait for confirmation before running it.