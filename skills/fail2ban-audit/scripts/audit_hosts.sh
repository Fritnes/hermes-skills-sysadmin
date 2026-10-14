#!/usr/bin/env bash
# Run audit.sh against several hosts in parallel and print a summary table.
# usage: audit_hosts.sh user@host1 user@host2 ...
# Full per-host reports are saved to $OUT (default: /tmp/f2b-audit-<timestamp>/).
here="$(cd "$(dirname "$0")" && pwd)"
OUT="${OUT:-/tmp/f2b-audit-$(date +%Y%m%d-%H%M%S)}"; mkdir -p "$OUT"
[ $# -eq 0 ] && { echo "usage: $0 user@host ..."; exit 2; }

for h in "$@"; do
  (
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$h" 'bash -s' < "$here/audit.sh" > "$OUT/$h.txt" 2>&1 \
      || echo "FAIL: ssh/audit exited non-zero (unreachable or auth failed)" >> "$OUT/$h.txt"
  ) &
done
wait

printf '%-32s %5s %5s %5s\n' HOST PASS WARN FAIL
for h in "$@"; do
  s=$(grep '^SUMMARY' "$OUT/$h.txt" | tail -1)
  if [ -n "$s" ]; then
    printf '%-32s %5s %5s %5s\n' "$h" \
      "$(echo "$s" | sed 's/.*pass=\([0-9]*\).*/\1/')" \
      "$(echo "$s" | sed 's/.*warn=\([0-9]*\).*/\1/')" \
      "$(echo "$s" | sed 's/.*fail=\([0-9]*\).*/\1/')"
  else
    printf '%-32s %s\n' "$h" "NO RESULT (see $OUT/$h.txt)"
  fi
done
echo "reports: $OUT"
