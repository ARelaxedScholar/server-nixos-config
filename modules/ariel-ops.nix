{ config, pkgs, ... }:

let
  ariel-host-health = pkgs.writeShellScriptBin "ariel-host-health" ''
    set -u

    ts="$(date -Is 2>/dev/null || true)"
    host="$(hostname 2>/dev/null || true)"

    failed_units="$(systemctl --failed --no-legend --no-pager 2>/dev/null \
      | awk 'NF {print $1}' \
      | paste -sd, - || true)"

    mem_avail_kb="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    mem_total_kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 1)"
    mem_avail_pct=$(( 100 * mem_avail_kb / mem_total_kb ))

    root_use_pct="$(df -P / 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print $5}' || echo 0)"
    load1="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo 0)"

    echo "ARIEL_HOST_HEALTH"
    echo "ts=$ts"
    echo "host=$host"
    echo "failed_units=''${failed_units:-none}"
    echo "mem_available_pct=$mem_avail_pct"
    echo "root_usage_pct=$root_use_pct"
    echo "load1=$load1"
  '';

  ariel-systemd-failed = pkgs.writeShellScriptBin "ariel-systemd-failed" ''
    set -u
    echo "ARIEL_SYSTEMD_FAILED"
    systemctl --failed --no-pager || true
  '';

  ariel-journal-tail = pkgs.writeShellScriptBin "ariel-journal-tail" ''
    set -u

    service="''${1:-}"

    case "$service" in
      hermes.service|watchtower.service|swagwatch-engine.service|postgresql.service)
        journalctl -u "$service" -n 200 --no-pager || true
        ;;
      *)
        echo "service_not_allowlisted=$service" >&2
        echo "allowed_services=hermes.service,watchtower.service,swagwatch-engine.service,postgresql.service" >&2
        exit 2
        ;;
    esac
  '';

  ariel-incident-report = pkgs.writeShellScriptBin "ariel-incident-report" ''
    set -u

    echo "========== ARIEL INCIDENT REPORT =========="
    echo
    ariel-host-health || true
    echo
    ariel-systemd-failed || true
    echo
    echo "========== END =========="
  '';
in
{
  users.users.hermes = {
    extraGroups = [ "systemd-journal" ];

    # This fixes tools that try to execute as hermes through a shell.
    # It does NOT grant sudo.
    shell = pkgs.bashInteractive;
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/hermes/reports 0750 hermes hermes - -"
    "d /var/lib/hermes/.hermes/scripts 0750 hermes hermes - -"
  ];

  environment.systemPackages = [
    ariel-host-health
    ariel-systemd-failed
    ariel-journal-tail
    ariel-incident-report
  ];
}
