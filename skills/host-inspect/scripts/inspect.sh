#!/usr/bin/env bash
# Read-only host inspection collector.
# Usage (run ON the remote host, typically piped over SSH):
#   ssh user@host 'bash -s -- [--sudo] [sections]' < inspect.sh
# sections: comma list of system,resources,disk,mdraid,services,logs,network,firewall,security,containers,updates
#           default: all
# --sudo   : use `sudo -n` (non-interactive) for commands that need root. Never prompts.
# This script performs NO writes, restarts, installs or config changes.

set -u
export LC_ALL=C
SUDO=""
SECTIONS="all"
for a in "$@"; do
  case "$a" in
    --sudo) command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null && SUDO="sudo -n" ;;
    *) SECTIONS="$a" ;;
  esac
done

want() { [[ "$SECTIONS" == "all" || ",$SECTIONS," == *",$1,"* ]]; }
have() { command -v "$1" >/dev/null 2>&1; }
hdr()  { printf '\n===== %s =====\n' "$1"; }
run()  { # run a command with a timeout, never fail the script
  printf '$ %s\n' "$*"
  if have timeout; then timeout 20 "$@" 2>&1 | head -n 200; else "$@" 2>&1 | head -n 200; fi
  return 0
}
sh_run() { printf '$ %s\n' "$1"; if have timeout; then timeout 20 bash -c "$1" 2>&1 | head -n 200; else bash -c "$1" 2>&1 | head -n 200; fi; return 0; }

echo "inspect.sh started $(date -u +%FT%TZ) as $(id -un) sudo=${SUDO:+yes}${SUDO:-no}"

if want system; then
  hdr SYSTEM
  run uname -a
  sh_run 'grep -E "^(PRETTY_NAME|VERSION)=" /etc/os-release'
  run uptime
  have systemd-detect-virt && run systemd-detect-virt
  have timedatectl && run timedatectl
fi

if want resources; then
  hdr RESOURCES
  sh_run 'nproc; cat /proc/loadavg'
  run free -h
  sh_run 'grep -E "^(MemAvailable|SwapTotal|SwapFree|Dirty)" /proc/meminfo'
  have vmstat && run vmstat 1 3
  sh_run 'ps -eo pid,ppid,user,stat,%cpu,%mem,etime,comm --sort=-%cpu | head -n 11'
  sh_run 'ps -eo pid,user,stat,%cpu,%mem,rss,comm --sort=-rss | head -n 11'
  sh_run 'ps -eo stat,pid,ppid,comm | awk "\$1 ~ /^Z/" | head -n 20'
  sh_run 'cat /proc/pressure/cpu /proc/pressure/memory /proc/pressure/io 2>/dev/null'
  sh_run 'dmesg -T 2>/dev/null | grep -iE "out of memory|oom-killer|killed process" | tail -n 10'
fi

if want disk; then
  hdr DISK
  run df -hT -x tmpfs -x devtmpfs -x squashfs -x overlay
  run df -iT -x tmpfs -x devtmpfs -x squashfs -x overlay
  have lsblk && run lsblk -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINT,ROTA,STATE
  have iostat && run iostat -xz 1 2
  sh_run 'findmnt -rno TARGET,OPTIONS | grep -E "(^| )ro[ ,]" | head'
  if have smartctl; then
    for d in $(lsblk -dno NAME,TYPE 2>/dev/null | awk '$2=="disk"{print "/dev/"$1}'); do
      sh_run "$SUDO smartctl -H $d"
    done
  fi
fi

if want mdraid; then
  hdr MDRAID
  if [ -r /proc/mdstat ]; then
    run cat /proc/mdstat
    if have mdadm; then
      for md in $(awk '/^md/{print "/dev/"$1}' /proc/mdstat); do
        sh_run "$SUDO mdadm --detail $md"
      done
      sh_run "$SUDO mdadm --examine --scan"
    fi
    sh_run 'for f in /sys/block/md*/md/{sync_action,degraded,mismatch_cnt,sync_completed}; do [ -r "$f" ] && echo "$f: $(cat $f)"; done'
    sh_run 'cat /etc/mdadm/mdadm.conf /etc/mdadm.conf 2>/dev/null | grep -vE "^\s*#|^\s*$"'
  else
    echo "no /proc/mdstat (md driver not loaded / no md arrays)"
  fi
fi

if want services; then
  hdr SERVICES
  if have systemctl; then
    run systemctl --failed --no-pager --plain
    run systemctl list-units --type=service --state=running --no-pager --plain
    sh_run 'systemctl list-timers --no-pager --plain | head -n 20'
    sh_run 'systemctl is-system-running'
  else
    echo "systemctl not available"
  fi
fi

if want logs; then
  hdr LOGS
  if have journalctl; then
    sh_run "$SUDO journalctl -p err -b --no-pager -n 60"
    sh_run "$SUDO journalctl -k -p warning -b --no-pager -n 40"
    sh_run 'journalctl --disk-usage'
  fi
  sh_run 'dmesg -T 2>/dev/null | grep -iE "error|fail|i/o|ext4|xfs|btrfs|nvme|ata[0-9]|md[0-9]" | tail -n 30'
  sh_run 'ls -lS /var/log 2>/dev/null | head -n 12'
fi

if want network; then
  hdr NETWORK
  have ip && run ip -br addr
  have ip && run ip route
  have ip && run ip -s -br link
  sh_run 'cat /etc/resolv.conf'
  if have ss; then
    run ss -tulpn
    sh_run 'ss -s'
    sh_run 'ss -tan state established | wc -l'
  else
    have netstat && run netstat -tulpn
  fi
fi

if want firewall; then
  hdr FIREWALL
  have ufw       && sh_run "$SUDO ufw status verbose"
  have firewall-cmd && sh_run "$SUDO firewall-cmd --list-all"
  have nft       && sh_run "$SUDO nft list ruleset | head -n 120"
  have iptables  && sh_run "$SUDO iptables -S | head -n 80"
  have fail2ban-client && sh_run "$SUDO fail2ban-client status"
  [ -n "$SUDO" ] || echo "(firewall rules usually need root; re-run with --sudo if allowed)"
fi

if want security; then
  hdr SECURITY
  sh_run '$(command -v sshd || echo /usr/sbin/sshd) -T 2>/dev/null | grep -iE "^(permitrootlogin|passwordauthentication|pubkeyauthentication|port|permitemptypasswords|x11forwarding|allowusers|allowgroups|maxauthtries)"'
  [ -n "$SUDO" ] && sh_run "$SUDO sshd -T | grep -iE '^(permitrootlogin|passwordauthentication|pubkeyauthentication|port|permitemptypasswords|allowusers|maxauthtries)'"
  sh_run 'awk -F: "\$3==0{print \"uid0:\",\$1}" /etc/passwd'
  sh_run 'awk -F: "\$7 !~ /(nologin|false)\$/{print \$1\":\"\$3\":\"\$7}" /etc/passwd'
  sh_run 'getent group sudo wheel admin'
  sh_run "$SUDO awk -F: '(\$2==\"\"){print \"EMPTY PASSWORD:\",\$1}' /etc/shadow"
  sh_run 'last -n 10 -a 2>/dev/null'
  sh_run "$SUDO lastb -n 10 -a 2>/dev/null"
  sh_run "$SUDO journalctl -u ssh -u sshd --since '24 hours ago' --no-pager 2>/dev/null | grep -ciE 'failed password|invalid user'"
  sh_run 'find / -xdev -perm -4000 -type f 2>/dev/null | head -n 40'
  sh_run 'find /etc /home /root -xdev -type f -perm -0002 2>/dev/null | head -n 20'
  sh_run 'ls -la /root/.ssh /home/*/.ssh 2>/dev/null | head -n 40'
  sh_run 'getenforce 2>/dev/null; aa-status --enabled 2>/dev/null && echo apparmor-enabled'
  sh_run 'crontab -l >/dev/null 2>&1 && echo "user crontab: present" || echo "user crontab: unavailable or empty"'
  sh_run 'ls /etc/cron.d 2>/dev/null'
fi

if want containers; then
  hdr CONTAINERS
  for rt in docker podman; do
    if have $rt; then
      echo "--- $rt ---"
      sh_run "$SUDO $rt version --format '{{.Server.Version}}'"
      sh_run "$SUDO $rt ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'"
      sh_run "$SUDO $rt ps -a --filter status=exited --filter status=restarting --format '{{.Names}}: {{.Status}}'"
      sh_run "$SUDO $rt stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}'"
      sh_run "$SUDO $rt system df"
      sh_run "$SUDO $rt ps -q | xargs -r $SUDO $rt inspect --format '{{.Name}} privileged={{.HostConfig.Privileged}} netmode={{.HostConfig.NetworkMode}} restarts={{.RestartCount}}'"
    fi
  done
  have crictl && sh_run "$SUDO crictl ps -a | head -n 30"
  have docker || have podman || echo "no docker/podman found"
fi

if want updates; then
  hdr UPDATES
  if have apt-get; then
    sh_run 'apt list --upgradable 2>/dev/null | head -n 30'
    sh_run '[ -f /var/run/reboot-required ] && echo REBOOT REQUIRED && cat /var/run/reboot-required.pkgs 2>/dev/null'
  elif have dnf; then
    sh_run 'dnf -q check-update 2>/dev/null | head -n 30'
    sh_run 'needs-restarting -r 2>&1 | tail -n 3'
  elif have zypper; then
    sh_run 'zypper -q lu | head -n 30'
  fi
  sh_run 'uname -r; ls /boot/vmlinuz-* 2>/dev/null | tail -n 3'
fi

echo
echo "inspect.sh finished $(date -u +%FT%TZ)"
