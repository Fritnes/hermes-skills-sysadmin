# Ban backends: inspection reference

Contents: detecting the backend, nftables, iptables, firewalld, other actions, config files.

All commands need root (`sudo`). Over non-interactive SSH, prefix with `PATH="$PATH:/usr/sbin:/sbin"`.

## Detecting the backend

Ask the running daemon, not the config files (precedence between `jail.conf`, `jail.d/*`, `jail.local` and per-jail overrides makes grepping unreliable):

```bash
sudo fail2ban-client get <jail> actions        # action names in use for the jail
sudo fail2ban-client get <jail> action <name> actionban   # exact ban command
```

Typical default `banaction` values (some distros set `banaction_allports` too):

| Action name contains | Backend |
|---|---|
| `nftables` | nftables |
| `iptables-multiport`, `iptables-allports`, `iptables` | iptables |
| `iptables-ipset-proto*` | iptables + ipset |
| `firewallcmd-*` | firewalld |
| `hostsdeny` | `/etc/hosts.deny` (TCP Wrappers) |
| `route`, `blackhole` | blackhole routing |

## nftables

Default table `inet f2b-table`, one set per jail: `addr-set-<jail>` (IPv4) and `addr6-set-<jail>` (IPv6).

```bash
sudo nft list tables | grep f2b
sudo nft list set inet f2b-table addr-set-<jail>
sudo nft list ruleset | grep -A3 f2b        # the rules that reference the sets
```

Empty set while fail2ban reports bans means the action isn't writing to nftables. Check `actions` (maybe the jail uses an iptables action while the host runs nftables).

## iptables

Chains are named `f2b-<jail>` on current versions (older: `fail2ban-<jail>`).

```bash
sudo iptables -S | grep -E 'f2b|fail2ban'
sudo iptables -S f2b-<jail>                 # one -A line per banned IP, plus a RETURN rule
sudo ip6tables -S | grep f2b                # IPv6 handled separately
```

If the chain exists but the INPUT chain has no jump to it, bans are not enforced: `sudo iptables -S INPUT | grep f2b`.

## firewalld

```bash
sudo firewall-cmd --direct --get-all-rules
sudo firewall-cmd --direct --get-all-rules | grep -i f2b
sudo firewall-cmd --list-rich-rules | grep -i reject    # rich-rule based actions
```

The script cannot count elements for firewalld, so it reports a failed cross-check as "verify manually".

## Other actions

- `hostsdeny`: `grep -i fail2ban /etc/hosts.deny`. Only affects services built with TCP Wrappers, which is rare today.
- `ipset`: `sudo ipset list | grep -A5 f2b`.

## Config files

| Path | Purpose |
|---|---|
| `/etc/fail2ban/jail.conf` | Packaged defaults (don't edit) |
| `/etc/fail2ban/jail.local` | Local overrides (edit this) |
| `/etc/fail2ban/jail.d/*.conf` | Modular overrides (Debian style) |
| `/etc/fail2ban/filter.d/*.conf` | Log-matching filters |
| `/etc/fail2ban/action.d/*.conf` | Ban actions |

Validate any change with `sudo fail2ban-client -t` before reloading.
