#!/usr/bin/env bash
# fail2ban read-only audit. Runs ON the target host, fed over SSH:
#   ssh -o BatchMode=yes -o ConnectTimeout=10 user@host 'bash -s' < audit.sh
# Output: section headers plus verdict lines starting with PASS / WARN / FAIL / INFO,
# and a final "SUMMARY pass=N warn=N fail=N" line. Makes NO changes to the host.

main() {
  export PATH="$PATH:/usr/sbin:/sbin:/usr/local/sbin"
  pass=0; warn=0; fail=0
  P() { echo "PASS: $*"; pass=$((pass+1)); }
  W() { echo "WARN: $*"; warn=$((warn+1)); }
  F() { echo "FAIL: $*"; fail=$((fail+1)); }
  I() { echo "INFO: $*"; }

  # Privilege wrapper. stdin is /dev/null so nothing can swallow the piped script.
  if [ "$(id -u)" -eq 0 ]; then S() { "$@" </dev/null; }; LIMITED=0
  elif sudo -n true 2>/dev/null </dev/null; then S() { sudo -n "$@" </dev/null; }; LIMITED=0
  else S() { "$@" </dev/null; }; LIMITED=1
  fi

  echo "=== HOST ==="
  echo "host: $(hostname 2>/dev/null)  kernel: $(uname -r)"
  [ "$LIMITED" -eq 1 ] && W "no root or passwordless sudo: audit is limited, most checks will fail"

  if ! command -v fail2ban-client >/dev/null 2>&1; then
    F "fail2ban-client not found: fail2ban is not installed (or not on PATH)"
    echo "SUMMARY pass=$pass warn=$warn fail=$fail"; return
  fi

  echo; echo "=== SERVICE ==="
  I "version: $(S fail2ban-client -V 2>&1 | head -1)"
  act=$(systemctl is-active fail2ban 2>&1); ena=$(systemctl is-enabled fail2ban 2>&1)
  [ "$act" = "active" ] && P "service active" || F "service not active (state: $act)"
  [ "$ena" = "enabled" ] && P "service enabled at boot" || W "service not enabled at boot (state: $ena)"
  if S fail2ban-client ping 2>&1 | grep -qi pong; then P "daemon answers ping"
  else F "daemon does not answer ping (socket unreachable or permissions)"; fi

  echo; echo "=== JAILS ==="
  jails=$(S fail2ban-client status 2>&1 | sed -n 's/.*Jail list:[[:space:]]*//p' | tr ',' ' ')
  if [ -z "$jails" ]; then
    F "no active jails"
    echo "SUMMARY pass=$pass warn=$warn fail=$fail"; return
  fi
  P "active jails: $jails"
  if ss -tln 2>/dev/null | grep -qE ':22[[:space:]]'; then
    if echo "$jails" | grep -qi ssh; then P "sshd listening on :22 and an ssh jail is active"
    else W "sshd listening on :22 but no ssh jail is active"; fi
  fi
  if echo "$jails" | grep -qw recidive; then I "recidive jail active (repeat offenders)"
  else I "no recidive jail (optional: longer bans for repeat offenders)"; fi

  ADMIN_IP="${SSH_CLIENT%% *}"
  RULESET=""
  command -v nft >/dev/null 2>&1 && RULESET=$(S nft list ruleset 2>/dev/null)

  for j in $jails; do
    echo; echo "--- JAIL $j ---"
    st=$(S fail2ban-client status "$j" 2>&1)
    cur=$(echo "$st" | sed -n 's/.*Currently banned:[[:space:]]*//p' | head -1)
    tot=$(echo "$st" | sed -n 's/.*Total banned:[[:space:]]*//p' | head -1)
    curf=$(echo "$st" | sed -n 's/.*Currently failed:[[:space:]]*//p' | head -1)
    totf=$(echo "$st" | sed -n 's/.*Total failed:[[:space:]]*//p' | head -1)
    cur=${cur:-0}; tot=${tot:-0}
    I "failed now/total: ${curf:-?}/${totf:-?}   banned now/total: $cur/$tot"

    mr=$(S fail2ban-client get "$j" maxretry 2>&1)
    ft=$(S fail2ban-client get "$j" findtime 2>&1)
    bt=$(S fail2ban-client get "$j" bantime 2>&1)
    acts=$(S fail2ban-client get "$j" actions 2>&1 | tr '\n' ' ')
    ign=$(S fail2ban-client get "$j" ignoreip 2>&1)
    I "maxretry=$mr findtime=${ft}s bantime=${bt}s actions=[${acts}]"

    case "$mr" in ''|*[!0-9]*) ;; *) [ "$mr" -gt 10 ] && W "$j: maxretry=$mr is high (<=5 typical)";; esac
    case "$bt" in
      -1) W "$j: bantime=-1 (permanent bans: set is never cleaned up)";;
      ''|*[!0-9]*) ;;
      *) [ "$bt" -lt 300 ] && W "$j: bantime=${bt}s is very short";;
    esac
    case "$ft" in ''|*[!0-9]*) ;; *) [ "$ft" -lt 60 ] && W "$j: findtime=${ft}s is very short";; esac

    if echo "$ign" | grep -qi 'no ip'; then
      W "$j: ignoreip is empty (admin IPs could get locked out)"
    else
      P "$j: ignoreip configured"
      if [ -n "$ADMIN_IP" ]; then
        if echo "$ign" | grep -qF "$ADMIN_IP"; then I "your IP $ADMIN_IP is in ignoreip"
        else I "your IP $ADMIN_IP is NOT listed in ignoreip (covered only if inside a listed network)"; fi
      fi
    fi
    if [ -n "$ADMIN_IP" ] && echo "$st" | grep -qF "$ADMIN_IP"; then
      F "$j: your own IP $ADMIN_IP appears in this jail's status/ban list"
    fi

    # Cross-check: fail2ban's count vs elements actually present in the firewall
    fw=""; fwn=""
    if [ -n "$RULESET" ] && echo "$RULESET" | grep -qE "set addr6?-set-$j( |$)"; then
      fwn=$(echo "$RULESET" | awk -v j="$j" '
        $0 ~ ("^[ \t]*set addr6?-set-" j " \\{") {on=1; next}
        on && /^\t}$/ {on=0}
        on' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}|[0-9a-fA-F]*:[0-9a-fA-F:]+' | wc -l)
      fw="nftables"
    elif command -v iptables >/dev/null 2>&1 && S iptables -S "f2b-$j" >/dev/null 2>&1; then
      fwn=$(S iptables -S "f2b-$j" 2>/dev/null | grep -c -- '-A f2b-.* -s ')
      fw="iptables"
    fi
    if [ -n "$fw" ]; then
      if [ "$fwn" -gt "$cur" ]; then d=$((fwn-cur)); else d=$((cur-fwn)); fi
      if [ "$cur" -gt 0 ] && [ "$fwn" -eq 0 ]; then
        F "$j: fail2ban reports $cur bans but $fw holds none: bans are NOT enforced (action/backend mismatch?)"
      elif [ "$d" -le 2 ]; then P "$j: fail2ban ($cur) matches $fw ($fwn banned)"
      else W "$j: fail2ban reports $cur bans, $fw holds $fwn (differs by $d; may be timing or IPv6)"; fi
    elif [ "$cur" -gt 0 ]; then
      F "$j: $cur active bans but no f2b nft set or iptables chain found (firewalld/ipset/other action? verify manually)"
    else
      I "$j: no bans active, firewall cross-check skipped"
    fi
  done

  echo; echo "=== FIREWALL OBJECTS ==="
  [ -n "$RULESET" ] && I "nft f2b tables: $(echo "$RULESET" | grep -E '^table .*f2b' | tr '\n' ';')"
  command -v iptables >/dev/null 2>&1 && I "iptables f2b chains: $(S iptables -S 2>/dev/null | grep -E '^-N (f2b|fail2ban)' | tr '\n' ';')"
  command -v firewall-cmd >/dev/null 2>&1 && I "firewalld direct rules matching f2b: $(S firewall-cmd --direct --get-all-rules 2>/dev/null | grep -ci 'f2b\|fail2ban')"

  echo; echo "=== LOGS (last 24h) ==="
  out=$(S journalctl -u fail2ban --since '24 hours ago' --no-pager 2>&1)
  if [ -z "$out" ] || echo "$out" | grep -qE 'No entries|not seeing messages'; then
    out=$(S tail -n 500 /var/log/fail2ban.log 2>&1); src="/var/log/fail2ban.log, last 500 lines"
  else src="journalctl"; fi
  errpat=' (ERROR|CRITICAL) |\[ERROR\]|\[CRITICAL\]'
  errs=$(echo "$out" | grep -cE "$errpat")
  if [ "$errs" -eq 0 ]; then P "no ERROR/CRITICAL entries in logs ($src)"
  else W "$errs ERROR/CRITICAL log entries ($src); last 5 below"; echo "$out" | grep -E "$errpat" | tail -5; fi
  I "recent activity:"; echo "$out" | tail -8

  echo; echo "SUMMARY pass=$pass warn=$warn fail=$fail"
}
main
exit
