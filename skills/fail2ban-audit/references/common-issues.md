# Common findings and fixes

Contents: finding table, enabling a jail, hardening notes.

Fixes below are suggestions. Get user confirmation before applying any of them.

## Finding table

| Finding | Likely cause | Suggested fix |
|---|---|---|
| FAIL: service not active | Crashed, or config error | `systemctl status fail2ban`; `sudo fail2ban-client -t` to validate config; check `/var/log/fail2ban.log` |
| FAIL: daemon does not answer ping | Socket missing or permission problem | Run with sudo; check service is really running |
| FAIL: no active jails | No jail enabled | Enable jails in `/etc/fail2ban/jail.local` (e.g. `[sshd]` with `enabled = true`) |
| WARN: sshd listens on :22, no ssh jail | sshd jail not enabled, or sshd runs on another port | Enable `[sshd]`; if the port is non-default, set `port =` |
| FAIL: bans reported but firewall holds none | Ban action doesn't match the firewall in use (e.g. iptables action on an nftables host), or firewall flushed/reloaded after fail2ban started | Check `fail2ban-client get <jail> actions`; set matching `banaction`; restart fail2ban after firewall reloads |
| WARN: counts differ by more than 2 | Timing/expiry, IPv6 sets, or partial enforcement | Re-run once; check `addr6-set-*` / `ip6tables`; if persistent, treat like the FAIL above |
| WARN: ignoreip empty | Not configured | Add admin/office/monitoring IPs to `ignoreip` in `[DEFAULT]` (keep `127.0.0.1/8 ::1`) |
| FAIL: your own IP appears in ban list | Locked yourself out risk | Unban from console: `fail2ban-client set <jail> unbanip <ip>`; add the IP to `ignoreip` |
| WARN: bantime=-1 | Permanent bans accumulate forever | Use finite times (`1d`, `1w`), or `bantime.increment = true` plus a `recidive` jail |
| WARN: maxretry high | Attackers get many free attempts | Lower to 3-5 for auth-type jails |
| WARN: findtime very short | Slow brute-force isn't detected | Use 10m or more |
| WARN: ERROR/CRITICAL in logs | Missing logpath, bad filter, backend problem | Read the entries; common: "Failed to access log file" (wrong `logpath`), "Unable to find a corresponding IP" |
| High `Total failed`, `Total banned` stays 0 | Filter regex doesn't match log format | Test: `fail2ban-regex /path/to/log /etc/fail2ban/filter.d/<filter>.conf` |
| Journal shows "No entries" | fail2ban logs to a file | Use `/var/log/fail2ban.log` (the script falls back automatically) |

## Enabling an additional jail

fail2ban does not ship a `grafana` filter. Create `filter.d/grafana.conf` first, or the jail will fail to start. Example of the write step (note `tee`, since a plain `>>` redirect would run as the unprivileged user):

```bash
sudo tee -a /etc/fail2ban/jail.local >/dev/null <<'EOF'
[grafana]
enabled  = true
port     = 3000
filter   = grafana
logpath  = /var/log/grafana/grafana.log
maxretry = 5
bantime  = 1d
EOF
sudo fail2ban-client -t && sudo systemctl reload fail2ban
```

## Hardening notes

- **Finite ban times** (`1d`, `1w`) are easier to clean up than permanent bans; pair with `bantime.increment` or `recidive` for repeat offenders.
- **Allowlist**: set `ignoreip` in `[DEFAULT]` to trusted IPs/networks.
- **Notifications**: `action = %(action_mwl)s` sends email with whois and log lines on bans (needs a working MTA).
- **IPv6**: make sure the ban action covers IPv6 if services are exposed over it.
- **Firewall reloads** can flush fail2ban's rules; restart fail2ban after them.
