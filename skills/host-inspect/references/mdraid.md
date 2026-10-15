# mdraid (Linux software RAID) inspection

Read-only commands: `cat /proc/mdstat`, `mdadm --detail /dev/mdX`, `mdadm --examine /dev/sdXN`, `mdadm --examine --scan`, `smartctl -a /dev/sdX`, `cat /sys/block/mdX/md/{degraded,sync_action,mismatch_cnt}`, `journalctl -k | grep -i md`.

## Reading /proc/mdstat
```
md0 : active raid1 sdb1[1] sda1[0]
      976630464 blocks super 1.2 [2/2] [UU]
```
- `[2/2] [UU]` healthy. `[2/1] [U_]` or `[_U]` = **degraded**, one member missing/failed. Underscore position = missing slot.
- `(F)` after a device = faulted. `(S)` = spare. `(W)` write-mostly.
- `recovery = 12.3% ... finish=95min` = rebuilding; array is vulnerable until done. `resync`/`check`/`repair` = scrub or initial sync.
- `inactive` = array not started (missing members, assembly problem). Treat as CRITICAL.
- `bitmap:` line present is good (fast resync after unclean shutdown).

## mdadm --detail checklist
- `State`: clean / active / degraded / recovering / resyncing. `clean, degraded` = still serving data, no redundancy (RAID1/5), RAID6 has one more disk of tolerance.
- `Active/Working/Failed/Spare Devices` counts; `Events` should match across members (`--examine`); a stale member with lower event count was out of sync.
- `Consistency Policy` (bitmap/resync); `Raid Level`; `Chunk Size`.

## Triage questions
1. Which member failed, and why? Check `journalctl -k` / `dmesg` for I/O errors, link resets (`ata`, `nvme`), and SMART on that disk (`Reallocated_Sector_Ct`, `Current_Pending_Sector`, `Offline_Uncorrectable`, `UDMA_CRC_Error_Count` -> cable). Check the *surviving* disks' SMART too - a rebuild will read them fully.
2. Is it a hot-spare setup? If a spare exists and rebuild is running, mostly watch.
3. `mismatch_cnt` > 0 after a `check`: for RAID1/10 can be benign (swap/temp data), otherwise investigate; don't recommend `repair` blindly.
4. Is `mdadm.conf` / initramfs consistent with arrays (`mdadm --examine --scan` vs `/etc/mdadm/mdadm.conf`)? Mismatch can cause arrays to come up as `md127` after reboot.
5. Is monitoring set up (`MAILADDR` in mdadm.conf, `mdmonitor` service)? Suggest if not.
6. Any other layers? LVM/LUKS/filesystem on top - `lsblk` to map.

## Suggested-fix patterns (to be run by the human, never by the agent)
Always preface: **confirm a current backup exists; rebuild stresses surviving disks.**

Replace a failed member (example):
```bash
mdadm --detail /dev/md0                      # confirm failed device name
mdadm /dev/md0 --fail /dev/sdb1              # only if not already (F)
mdadm /dev/md0 --remove /dev/sdb1
# physically replace disk, partition it identically to the healthy one
sfdisk -d /dev/sda | sfdisk /dev/sdb         # MBR/GPT clone (check device names twice!)
mdadm /dev/md0 --add /dev/sdb1
watch cat /proc/mdstat                       # monitor rebuild
```
Verify: `[UU]`, `State : clean`, `Failed Devices : 0`. Then update `mdadm.conf` + initramfs if array metadata changed (`update-initramfs -u` / `dracut -f`).

Run a scrub (low risk, schedule off-hours): `echo check > /sys/block/md0/md/sync_action`.

Don't suggest: `--create` on existing disks, `--zero-superblock` on a member you aren't sure about, `--force` assemble without understanding event counts, or rebooting a degraded array with a flaky disk as a "fix".
