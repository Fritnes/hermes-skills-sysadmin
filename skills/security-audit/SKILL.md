---
name: security-audit
description: "Use for read-only sysadmin security reviews of SSH configuration, listening ports, pending updates, selected file permissions, and firewall status. Resolve hosts through host-inventory and report findings by severity without applying fixes."
---

# Security Audit

Perform a bounded, read-only review of host security posture. State the audit scope and host OS; do not describe a limited host check as a penetration test or comprehensive compliance assessment.

## Audit workflow

1. Confirm the requested host(s), audit scope, and relevant standard or policy if one was specified.
2. Resolve each host through `host-inventory`. Carry forward its exact name, environment, OS, state, protection status, and connection route. For groups, show the resolved target list. Stop if the inventory or target is missing or ambiguous.
3. Select checks relevant to the host and scope. Use read-only commands and respect the host's OS and available tools. Examples:

   - SSH: `sshd -t` for configuration syntax and `sshd -T` for effective settings; inspect selected permissions with `stat`, not file contents.
   - Exposure: `ss -lntup` for listening TCP/UDP sockets. Explain that a listening socket is not by itself proof of internet exposure.
   - Firewall: inspect the active tool, such as `nft list ruleset`, `ufw status verbose`, or `iptables -S`; do not change rules.
   - Updates: list pending security updates with the host's package manager; do not install them.
   - Permissions: check only policy-relevant paths and modes. Do not recursively dump broad filesystem metadata.

4. Minimize privilege. If a command requires elevated access, explain why and request authorization rather than silently using `sudo`.
5. Capture evidence and limits: command, target, time, result, tool availability, and what the check cannot establish.

## Findings

Classify each finding as:

- **Critical:** credible immediate exposure or compromise requiring urgent owner attention.
- **High:** substantial weakness with a realistic path to impact.
- **Medium:** meaningful hardening gap or exposure with limited or conditional impact.
- **Low:** minor policy deviation or defense-in-depth improvement.
- **Informational:** observed configuration or a check limitation without a confirmed weakness.

For each finding, include evidence, affected `NAME (ENV)`, impact, confidence, and a recommended next step. Clearly distinguish a verified weakness from a possible concern. Do not claim compliance from a small set of checks.

## Safety boundaries

- This skill is read-only. Do not edit SSH configuration, change permissions, close ports, change firewall rules, install updates, or disable services.
- Do not expose private keys, passwords, tokens, environment variables, or sensitive file contents in output. Redact secrets found accidentally and tell the user where they were found without repeating them.
- Hand off remediation to the relevant skill and obtain explicit approval for each change and target.

## Example

For "audit SSH and exposed ports on web-01", resolve `web-01`, run scoped SSH syntax/effective-setting checks and inspect listening sockets, then report evidence and severity. Do not change `sshd_config` or firewall rules.