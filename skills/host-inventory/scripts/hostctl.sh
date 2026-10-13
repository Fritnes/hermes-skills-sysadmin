#!/usr/bin/env bash
# hostctl - manage a plain-text host inventory. No dependencies beyond bash, awk, ssh.
#
# Inventory file: $HOSTCTL_INVENTORY (default ./hosts.conf)
# Format, one host per line, 11 required fields plus optional state and tags:
#   name|address|user|port|jump|os|role|env|owner|protected|notes|state|tags
# "jump" is empty (direct connection), the name of another inventory host
# (the bastion), or a literal user@host[:port].
#
# Usage:
#   hostctl.sh list [--env ENV] [--role ROLE] [--state STATE] [--tag TAG]
#   hostctl.sh names [--env ENV] [--role ROLE] [--state STATE] [--tag TAG]
#   hostctl.sh show NAME
#   hostctl.sh add NAME ADDRESS USER OS ROLE ENV OWNER [--port N] [--jump J] [--protected yes|no] [--state ACTIVE] [--tags TAG1,TAG2] [--notes TEXT]
#   hostctl.sh remove NAME --yes                    (marks as decommissioned, keeps the line)
#   hostctl.sh validate
#   hostctl.sh ping NAME                            (read-only SSH reachability test, via jump if set)
set -euo pipefail

INV="${HOSTCTL_INVENTORY:-./hosts.conf}"
LOG="$(dirname "$INV")/hosts.log"
ENVS="prod staging dev"
ALLOWED_STATES="active maintenance failed pending decommissioned"
NF_EXPECTED=13
NF_EXPECTED_LEGACY=11

die() { echo "error: $*" >&2; exit 1; }
need_inv() { [ -f "$INV" ] || die "inventory not found: $INV (set HOSTCTL_INVENTORY or create it from assets/hosts.conf.example)"; }
log() { printf '%s | %s | %s\n' "$(date +%F)" "$1" "$2" >> "$LOG"; }
trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }

# Print the line for host $1 (exact name match), or nothing.
find_host() { awk -F'|' -v n="$1" '/^[[:space:]]*(#|$)/{next} {gsub(/^[ \t]+|[ \t]+$/,"",$1); if($1==n){print; exit}}' "$INV"; }

# Turn a jump value into user@host[:port] for ssh -J. Inventory name or literal.
resolve_jump() {
  local j; j="$(trim "$1")"; [ -n "$j" ] || return 0
  local line; line="$(find_host "$j")"
  if [ -n "$line" ]; then
    local _n a u p
    IFS='|' read -r _n a u p _ <<<"$line"
    printf '%s@%s:%s' "$(trim "$u")" "$(trim "$a")" "$(trim "$p")"
  else
    printf '%s' "$j"
  fi
}

cmd_list() {
  need_inv
  local mode="$1"; shift
  local env="" role="" state="" tag=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --env) env="$2"; shift 2;;
      --role) role="$2"; shift 2;;
      --state) state="$2"; shift 2;;
      --tag) tag="$2"; shift 2;;
      *) die "unknown option: $1";;
    esac
  done
  awk -F'|' -v env="$env" -v role="$role" -v state="$state" -v tag="$tag" -v mode="$mode" '
    function t(s){gsub(/^[ \t]+|[ \t]+$/,"",s); return s}
    function has_tag(s, tg) { s = "," t(s) ","; tg = "," tg ","; return index(s, tg) > 0 }
    /^[[:space:]]*(#|$)/{next}
    {
      st = (NF >= 12) ? t($12) : "active"
      tg = (NF >= 13) ? t($13) : ""
      if(env != "" && t($8) != env) next
      if(role != "" && t($7) != role) next
      if(state != "" && st != state) next
      if(tag != "" && !has_tag(tg, tag)) next
      if(mode == "names") print t($1)
      else printf "%-16s %-18s %-8s %-8s %-10s %-9s %-14s %-10s %s\n", t($1), t($2), t($3), t($7), t($6), t($8), st, (tg==""?"-":tg), (t($10)=="yes"?"protected":"")
    }
  ' "$INV"
}

cmd_show() {
  need_inv; [ $# -eq 1 ] || die "usage: show NAME"
  local line; line="$(find_host "$1")"; [ -n "$line" ] || die "host not found: $1"
  echo "$line" | awk -F'|' '
    function t(s){gsub(/^[ \t]+|[ \t]+$/,"",s); return s}
    {
      st = (NF >= 12) ? t($12) : "active"
      tg = (NF >= 13) ? t($13) : ""
      printf "name:      %s\naddress:   %s\nuser:      %s\nport:      %s\njump:      %s\nos:        %s\nrole:      %s\nenv:       %s\nowner:     %s\nprotected: %s\nnotes:     %s\nstate:     %s\ntags:      %s\n",
        t($1),t($2),t($3),t($4),(t($5)==""?"(direct)":t($5)),t($6),t($7),t($8),t($9),t($10),t($11),st,(tg==""?"(none)":tg)
    }'
}

cmd_add() {
  need_inv
  [ $# -ge 7 ] || die "usage: add NAME ADDRESS USER OS ROLE ENV OWNER [--port N] [--jump J] [--protected yes|no] [--state STATE] [--tags TAG1,TAG2] [--notes TEXT]"
  local name="$1" addr="$2" user="$3" os="$4" role="$5" env="$6" owner="$7"; shift 7
  local port=22 jump="" prot="" state="active" tags="" notes=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --port) port="$2"; shift 2;;
      --jump) jump="$2"; shift 2;;
      --protected) prot="$2"; shift 2;;
      --state) state="$2"; shift 2;;
      --tags) tags="$2"; shift 2;;
      --notes) notes="$2"; shift 2;;
      *) die "unknown option: $1";;
    esac
  done
  for v in "$name" "$addr" "$user" "$os" "$role" "$env" "$owner" "$jump" "$notes" "$state" "$tags"; do
    case "$v" in *"|"*) die "values must not contain '|'";; esac
  done
  [[ "$name" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || die "invalid name '$name' (lowercase letters, digits, . _ -)"
  [[ "$port" =~ ^[0-9]+$ ]] || die "port must be a number"
  case " $ALLOWED_STATES " in *" $state "*) ;; *) die "--state must be one of: $ALLOWED_STATES";; esac
  case " $ENVS " in *" $env "*) ;; *) die "env must be one of: $ENVS";; esac
  [ -n "$prot" ] || { [ "$env" = prod ] && prot=yes || prot=no; }
  case "$prot" in yes|no) ;; *) die "--protected must be yes or no";; esac
  [ "$jump" != "$name" ] || die "a host cannot be its own jump host"
  [ "$user" != root ] || echo "warning: user is root; prefer a least-privilege account" >&2
  [ -z "$(find_host "$name")" ] || die "host already exists: $name"
  awk -F'|' -v a="$addr" '/^[[:space:]]*(#|$)/{next} {gsub(/^[ \t]+|[ \t]+$/,"",$2); if($2==a) f=1} END{exit f?0:1}' "$INV" \
    && die "address $addr is already used by another host"
  cp "$INV" "$INV.bak"
  printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "$name" "$addr" "$user" "$port" "$jump" "$os" "$role" "$env" "$owner" "$prot" "$notes" "$state" "$tags" >> "$INV"
  log "add" "$name ($env) $addr${jump:+ via $jump} [$state]"
  echo "added $name ($env, state=$state, protected=$prot${jump:+, via $jump}). Backup: $INV.bak"
}

cmd_remove() {
  need_inv
  [ $# -eq 2 ] && [ "$2" = "--yes" ] || die "usage: remove NAME --yes  (the user must confirm first)"
  [ -n "$(find_host "$1")" ] || die "host not found: $1"
  local deps; deps="$(awk -F'|' -v n="$1" '/^[[:space:]]*(#|$)/{next} {j=$5; gsub(/^[ \t]+|[ \t]+$/,"",j); if(j==n){x=$1; gsub(/^[ \t]+|[ \t]+$/,"",x); printf "%s ", x}}' "$INV")"
  [ -z "$deps" ] || die "$1 is the jump host for: $deps- update those first"
  cp "$INV" "$INV.bak"
  awk -F'|' -v n="$1" -v d="$(date +%F)" '
    { key=$1; gsub(/^[ \t]+|[ \t]+$/,"",key)
      if(!/^[[:space:]]*#/ && key==n) print "# DECOMMISSIONED " d " " $0; else print }
  ' "$INV.bak" > "$INV"
  log "remove" "$1 marked decommissioned"
  echo "$1 marked as decommissioned. Backup: $INV.bak"
}

cmd_validate() {
  need_inv
  awk -F'|' -v envs="$ENVS" -v nfe1="$NF_EXPECTED" -v nfe2="$NF_EXPECTED_LEGACY" '
    function t(s){gsub(/^[ \t]+|[ \t]+$/,"",s); return s}
    BEGIN{
      n=split(envs,e," "); for(i=1;i<=n;i++) okenv[e[i]]=1
      split("name address user port - os role env owner",lab," ")
      nstate=split("active maintenance failed pending decommissioned",states," ")
      for(i=1;i<=nstate;i++) state_ok[states[i]]=1
    }
    /^[[:space:]]*(#|$)/{next}
    {
      count++
      if(NF!=nfe1 && NF!=nfe2){printf "line %d: expected %d or %d fields, found %d\n",NR,nfe1,nfe2,NF; bad++; next}
      state = (NF >= 12) ? t($12) : "active"
      tags = (NF >= 13) ? t($13) : ""
      name=t($1); names[name]=1; jumps[name]=t($5)
      for(i=1;i<=9;i++) if(i!=5 && t($i)==""){printf "%s: empty field \"%s\"\n",name,lab[i]; bad++}
      if(t($4)!="" && t($4) !~ /^[0-9]+$/){printf "%s: port is not a number\n",name; bad++}
      if(!(t($8) in okenv)){printf "%s: unknown env \"%s\"\n",name,t($8); bad++}
      if(t($10)!="yes" && t($10)!="no"){printf "%s: protected must be yes or no\n",name; bad++}
      if(t($8)=="prod" && t($10)=="no"){printf "%s: prod host with protected=no (intended?)\n",name; bad++}
      if(state == "") state = "active"
      if(!(state in state_ok)){printf "%s: unknown state \"%s\"\n",name,state; bad++}
      if(t($3)=="root"){printf "%s: user is root; prefer a least-privilege account\n",name; bad++}
      if(t($5)==name){printf "%s: is its own jump host\n",name; bad++}
      if(t($11) ~ /(password|passwd|token|secret)[ ]*[:=]/ || t($11) ~ /BEGIN [A-Z ]*PRIVATE KEY/){printf "%s: notes look like they contain a secret\n",name; bad++}
      if(name in seenname){printf "%s: duplicate name\n",name; bad++}
      seenname[name]=1
      a=t($2)
      if(a in seenaddr){printf "%s: address %s also used by %s\n",name,a,seenaddr[a]; bad++}
      seenaddr[a]=name
      if(tags != "" && tags ~ /[|]/){printf "%s: tags must not contain a pipe character\n",name; bad++}
    }
    END{
      for(h in jumps){ cur=h; steps=0
        while(cur in jumps && jumps[cur]!="" && (jumps[cur] in names) && steps<20){cur=jumps[cur]; steps++; if(cur==h){printf "%s: jump host chain loops back to itself\n",h; bad++; break}}
      }
      if(bad>0){printf "%d problem(s) in %d hosts\n",bad,count; exit 1} printf "OK: %d hosts, no problems\n",count }
  ' "$INV"
}

cmd_ping() {
  need_inv; [ $# -eq 1 ] || die "usage: ping NAME"
  local line; line="$(find_host "$1")"; [ -n "$line" ] || die "host not found: $1"
  local name addr user port jump os role env owner protected notes state tags
  IFS='|' read -r name addr user port jump os role env owner protected notes state tags <<<"$line"
  name="$(trim "$name")"; addr="$(trim "$addr")"; user="$(trim "$user")"; port="$(trim "$port")"; env="$(trim "$env")"; state="$(trim "${state:-active}")"
  local jarg=() via; via="$(resolve_jump "$jump")"
  [ -z "$via" ] || jarg=(-J "$via")
  echo "testing $name ($env) [$state] as $user@$addr:$port${via:+ via $via} ..."
  if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=yes "${jarg[@]}" -p "$port" "$user@$addr" true 2>/tmp/hostctl_ping.err; then
    echo "reachable"
  else
    echo "NOT reachable: $(head -n1 /tmp/hostctl_ping.err)"; exit 1
  fi
}

sub="${1:-}"; [ $# -gt 0 ] && shift || true
case "$sub" in
  list)     cmd_list table "$@";;
  names)    cmd_list names "$@";;
  show)     cmd_show "$@";;
  add)      cmd_add "$@";;
  remove)   cmd_remove "$@";;
  validate) cmd_validate;;
  ping)     cmd_ping "$@";;
  *) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 2;;
esac
