# Rootless Docker daemon, started on demand as a transient systemd user unit.
# There is no system Docker; docker compose (node-api-database's test runner,
# appenginenode-download's debug) needs one: docker-daemon start|stop|status|logs
# DOCKERD_ROOTLESS and DOCKERD_PATH come from runtimeEnv in home/bookcreator.nix.
unit=docker-daemon
socket="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/docker.sock"

case "${1:-}" in
  start)
    if systemctl --user --quiet is-active "$unit"; then
      echo "docker-daemon: already running ($socket)"
      exit 0
    fi
    # Same unit settings as the NixOS rootless Docker module, except that
    # TimeoutSec is infinity: in a unit file 0 means no timeout, but systemd-run
    # passes it on as a zero timeout and the start fails at once.
    if ! systemd-run --user --quiet --collect --unit="$unit" \
      --description="Rootless Docker" \
      --setenv=PATH="$DOCKERD_PATH" \
      --property=Type=notify --property=NotifyAccess=all --property=Delegate=yes \
      --property=KillMode=mixed --property=TimeoutSec=infinity \
      --property=LimitNOFILE=infinity --property=LimitNPROC=infinity \
      "$DOCKERD_ROOTLESS"; then
      journalctl --user --unit="$unit" --lines=30 --no-pager >&2
      exit 1
    fi
    echo "docker-daemon: running ($socket)"
    ;;
  stop)
    systemctl --user stop "$unit"
    ;;
  status)
    systemctl --user --no-pager status "$unit"
    ;;
  logs)
    shift
    journalctl --user --unit="$unit" "$@"
    ;;
  *)
    echo "usage: docker-daemon start|stop|status|logs" >&2
    exit 2
    ;;
esac
