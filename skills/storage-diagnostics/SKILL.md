---
name: storage-diagnostics
description: "Use for Linux storage diagnosis: filesystem capacity, inode exhaustion, mounts, block devices, SMART or NVMe health, and LVM capacity. Resolve hosts through host-inventory and inspect before recommending any cleanup or storage change."
---

# Storage Diagnostics

Find evidence for storage pressure or device health issues without changing data or storage layout. Begin with filesystem and inode use; expand only where the results point.

## Resolve and inspect

1. Resolve the target through `host-inventory`, carrying forward exact host, environment, address, SSH user, port, jump host, state, and protection status. For a group, show the filtered targets and resolve each host. Stop if the inventory or target is missing or ambiguous.
2. Gather a small baseline:

   ```bash
   df -hT
   df -ih
   findmnt
   lsblk -f
   ```

3. For a pressured filesystem, identify large directories with a scoped, read-only command such as `du -xhd1 /var`. Avoid unrestricted scans of mounted network filesystems or directories likely to contain private user data.
4. If available and relevant, inspect device health with `smartctl -H DEVICE`, `smartctl -A DEVICE`, or the vendor-supported NVMe health command. Use `pvs`, `vgs`, and `lvs` to inspect LVM capacity. Do not start a SMART self-test unless separately requested and approved.
5. Use privilege escalation only when necessary and explicitly permitted. Report unavailable commands and permission limits instead of silently installing tools or escalating.

## Interpret and report

Report filesystem and inode percentages separately, identify the affected mount and device, distinguish allocated capacity from directory contents, and note SMART warnings or LVM free extents. Treat thresholds as indicators, not proof of a fault. Recommend the smallest next investigation and identify the owning application or data before proposing cleanup.

## Safety boundaries

- Diagnostics are read-only. Never delete, truncate, move, or compress data; do not run `fsck`, resize filesystems or volumes, change mount options, repartition, or discard blocks as part of diagnosis.
- Never clean logs, caches, or backups based only on size. Ask for retention policy and owner approval before any cleanup plan is executed.
- Avoid copying file contents or exposing names of sensitive files in reports; summarize paths only as needed.

## Example

For "find what is filling /var on web-01", resolve `web-01`, inspect `df -hT` and `df -ih`, then use a depth-limited `du` on the affected filesystem. Report the largest directories and suggest an owner-reviewed next step without deleting anything.