---
name: incident-triage
description: "Use for sysadmin incident triage, outages, degraded services, unexpected latency, host failures, and requests to correlate logs or health signals. Resolve every managed target through host-inventory and gather evidence without making changes."
---

# Incident Triage

Build a concise, evidence-based picture of an operational problem and recommend the next diagnostic steps. This skill coordinates `host-inventory`, `linux-healthcheck`, `network-diagnostics`, and `service-operations`; it does not replace their detailed procedures.

## Triage workflow

1. Establish the reported symptom, when it began, impact, affected service, recent changes, and whether the issue is ongoing. Ask only for details needed to scope checks.
2. Resolve each managed source and destination with `host-inventory`. Carry forward the exact host, environment, address, SSH user, port, jump host, state, and protection status. For groups, show the resolved target list before running checks. Stop if the inventory or target is missing or ambiguous.
3. Start with the narrowest read-only checks that can distinguish likely causes. Use `linux-healthcheck` for host pressure, `network-diagnostics` for path or connectivity issues, and `service-operations` for unit state and bounded logs.
4. Keep checks scoped to the incident's time window and affected units. Record command, target, timestamp, observed result, and any limitation. Redact secrets and personal data from logs.
5. Separate confirmed facts from hypotheses. Rank likely causes by evidence and state confidence; do not present a correlation as proof.

## Report

Return:

- affected target(s) as `NAME (ENV)` and the reported impact
- confirmed findings with timestamps and concise evidence
- plausible causes, clearly marked as hypotheses
- the smallest next checks, in priority order
- any missing information or access limitations

## Safety boundaries

- Triage is read-only. Do not restart services, kill processes, edit files, patch, restore backups, or change routes/firewall rules.
- Do not run broad commands across a fleet unless the user requested that scope and the inventory-resolved target list is shown.
- Do not dump full journals, environment variables, credential files, or unrelated user data.
- If a check suggests a change, explain the evidence and hand off to the relevant skill. Get explicit approval before any change.

## Example

For "web-01 is responding slowly", resolve `web-01` and its environment first, then gather a short health summary and inspect only relevant service and network signals. Report what was observed and recommend the next discriminating check; do not restart nginx as part of triage.