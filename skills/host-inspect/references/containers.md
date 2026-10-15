# Container inspection (Docker / Podman)

Read-only commands: `docker ps -a`, `docker stats --no-stream`, `docker system df`, `docker inspect <c>` (beware: prints env vars - redact secrets), `docker logs --tail 100 <c>`, `docker events --since 1h --until now`, `docker network ls`, `docker volume ls`, `docker info`. Same for `podman`. For rootless Podman, run as that user.

## Triage
- **Exited / Restarting / Unhealthy**: `docker inspect --format '{{.State.ExitCode}} {{.State.OOMKilled}} {{.RestartCount}}' <c>`; exit 137 + OOMKilled=true -> memory limit; 139 segfault; 1 app error -> read `docker logs --tail 200`.
- **Restart loops**: high `RestartCount` + short uptime. Check logs and whether dependencies (DB, volume mounts, network) exist.
- **Resource hogs**: `docker stats --no-stream`; containers without limits (`HostConfig.Memory == 0`) can starve the host.
- **Disk**: `docker system df -v`; large json logs in `/var/lib/docker/containers/*/*-json.log` (suggest log rotation: `--log-opt max-size=10m --log-opt max-file=3` or daemon.json). Dangling images/volumes: *suggest* `docker image prune` / `docker builder prune` but never run it.
- **Healthchecks**: `docker inspect --format '{{json .State.Health}}' <c>`.
- **Daemon health**: `systemctl status docker`, `journalctl -u docker -n 100`.

## Security checks
- `Privileged=true`, `--pid=host`, `--network=host`, mounted `/var/run/docker.sock`, added capabilities (`CapAdd`), mounts of `/`, `/etc`, `/root`.
- Published ports on `0.0.0.0` (`docker ps` Ports column) - especially DBs, Redis, Docker API (2375/2376 unauthenticated TCP = CRITICAL).
- Docker bypasses UFW/firewalld for published ports; check `iptables -S DOCKER-USER` and suggest binding to 127.0.0.1 (`-p 127.0.0.1:5432:5432`) or filtering in DOCKER-USER.
- Running as root inside container (`.Config.User` empty), images using `:latest` or very old, unknown registries.
- Secrets in `Config.Env` -> flag, redact, suggest secrets/env-files.

## Kubernetes nodes
If `kubectl`/`crictl` exists: `kubectl get nodes,pods -A | grep -v Running`, `kubectl describe node`, `crictl ps -a`. Same read-only rule applies.

## Suggested-fix examples (human runs)
```bash
docker logs --tail 200 <name>                         # read first
docker update --memory 1g --memory-swap 1g <name>     # live limit change
docker compose up -d --force-recreate <svc>           # after config fix; note brief downtime
docker image prune -a --filter "until=720h"           # reclaim space; check `docker images` first
```
Always state downtime/data risk (volumes, anonymous volumes lost on `rm -v`).
