#!/usr/bin/env bash
# Run inspect.sh on a target through ANY transport that gives a bash shell.
#
#   run.sh [--sudo] [--sections a,b,c] [-- <transport command...>]
#
# No transport command  -> inspect the local machine.
# Transport command     -> must read a script from stdin and run the given args, e.g.:
#   run.sh --sudo -- ssh -o BatchMode=yes user@host
#   run.sh -- ssh -J bastion user@host
#   run.sh -- docker exec -i mycontainer
#   run.sh -- kubectl exec -i mypod --
#   run.sh -- incus exec myvm --
#   run.sh -- sudo nsenter -t 1 -m -u -n -p      # host view from a privileged container
# Output goes to stdout. Nothing is written to the target.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGS=()
SECTIONS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --sudo) ARGS+=("--sudo"); shift ;;
    --sections) SECTIONS="${2:-}"; shift 2 ;;
    --) shift; break ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
[ -n "$SECTIONS" ] && ARGS+=("$SECTIONS")

if [ $# -eq 0 ]; then
  exec bash -s -- "${ARGS[@]}" < "$HERE/inspect.sh"
else
  exec "$@" bash -s -- "${ARGS[@]}" < "$HERE/inspect.sh"
fi
