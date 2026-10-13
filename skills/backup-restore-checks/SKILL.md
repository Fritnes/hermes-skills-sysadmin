---
name: backup-restore-checks
description: "Use to review backup freshness, coverage, retention, job results, restore readiness, or plan a backup restore test. Resolve source and backup hosts through host-inventory; never overwrite live data or assume a backup is usable without a restore test."
---

# Backup and Restore Checks

Assess whether the requested data is covered by a known backup, whether recent backup runs succeeded, and whether a controlled restore test is possible. Backup products and policies vary; identify the actual tool and documented recovery procedure instead of assuming one.

## Assess coverage and freshness

1. Clarify the source host, data or service, recovery point objective if known, and the expected backup schedule.
2. Resolve the source and any inventory-managed backup target with `host-inventory`. Confirm environment, owner, state, and access path. Stop if a target is missing or ambiguous.
3. Identify the configured backup tool and authoritative job or repository. Read status, last successful run, covered paths or databases, retention, and available restore points using that tool's read-only inspection commands.
4. Compare the latest successful recovery point with the expected schedule. Distinguish "job succeeded" from "data is restorable"; note gaps in application consistency, coverage, or retention.
5. Do not display secrets, repository credentials, encryption keys, or full configuration values. Do not infer backup coverage from a directory name alone.

## Plan a restore test

- Propose a specific restore point, data scope, isolated destination, validation checks, owner, and cleanup plan.
- Require explicit confirmation before starting a restore test because it writes data, even when the destination is intended to be isolated.
- Never restore over a production path, live database, or original host as a test. If isolation cannot be demonstrated, stop and request a safer destination.
- Follow the backup product's documented restore procedure. Avoid inventing flags or assuming the tool, encryption setup, or consistency model.
- Validate restored files or application data using checksums, expected contents, and application-native integrity checks where appropriate. Record elapsed time and any missing or corrupt items.

## Report

Summarize covered data, latest successful backup time, expected versus observed freshness, available restore points, retention gaps, restore-test status, and the next action. Label an untested backup as "not yet restore-verified" rather than "good".

## Example

For "check whether db-01 has a recent restorable backup", resolve `db-01`, identify its configured backup workflow, inspect the latest run and restore points, and report freshness. Propose an isolated database restore test; do not run it until the user confirms the destination and test window.