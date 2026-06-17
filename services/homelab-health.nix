{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.homelabHealth;

  report = pkgs.writeShellApplication {
    name = "homelab-health";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      docker
      findutils
      gnugrep
      gnused
      iproute2
      procps
      systemd
      util-linux
      zfs
    ];
    text = ''
      set -euo pipefail

      log_section() {
        printf '\n== %s ==\n' "$1"
      }

      run_cmd() {
        local label="$1"
        shift
        log_section "$label"
        if "$@"; then
          true
        else
          echo "[warn] $label failed" >&2
        fi
      }

      check_url() {
        local url="$1"
        log_section "HEALTHCHECK: $url"
        if curl -fsS --max-time 5 "$url" >/dev/null; then
          echo "OK"
        else
          echo "FAIL"
        fi
      }

      check_path() {
        local path="$1"
        log_section "PATH USAGE: $path"
        if [ -e "$path" ]; then
          du -sh "$path" || true
          find "$path" -maxdepth 1 -type f 2>/dev/null | sed -n '1,5p' || true
        else
          echo "MISSING"
        fi
      }

      check_container_logs() {
        local name="$1"
        log_section "CONTAINER LOGS: $name"
        if docker logs --tail 120 "$name" >/tmp/homelab-health-logs 2>/dev/null; then
          sed -n '1,120p' /tmp/homelab-health-logs
        else
          echo "UNAVAILABLE"
        fi
      }

      echo "HOST: $(hostname -f 2>/dev/null || hostname)"
      echo "TIME: $(date -Is)"
      echo "UPTIME: $(uptime -p 2>/dev/null || uptime)"

      run_cmd "FAILED SYSTEMD UNITS" systemctl --failed --no-pager
      run_cmd "RECENT ERRORS" journalctl -p err -b --no-pager -n 100
      run_cmd "DISK USAGE" df -hT
      run_cmd "MEMORY" free -h
      run_cmd "NETWORK" ip -brief address
      run_cmd "DOCKER CONTAINERS" docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
      run_cmd "ZPOOL STATUS" zpool status
      run_cmd "ZFS DATASETS" zfs list -o name,used,avail,refer,mountpoint

      ${lib.optionalString (cfg.smartDevice != null) ''
      run_cmd "SMART ${cfg.smartDevice}" smartctl -a ${lib.escapeShellArg cfg.smartDevice}
      ''}

      ${lib.concatStringsSep "\n" (map (url: "check_url ${lib.escapeShellArg url}") cfg.healthUrls)}

      ${lib.concatStringsSep "\n" (map (path: "check_path ${lib.escapeShellArg path}") cfg.pathChecks)}

      ${lib.concatStringsSep "\n" (map (name: "check_container_logs ${lib.escapeShellArg name}") cfg.logTargets)}
    '';
  };
in
{
  options.services.homelabHealth = {
    enable = lib.mkEnableOption "Deterministic homelab health report and timer";

    smartDevice = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional SMART device path to inspect, e.g. /dev/sda.";
    };

    healthUrls = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "HTTP endpoints to curl during the health report.";
    };

    pathChecks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Paths whose disk usage and presence should be reported.";
    };

    logTargets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Container names whose recent logs should be included.";
    };

    reportPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/homelab-health/latest.txt";
      description = "Path where the latest report is stored.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ report ];

    systemd.tmpfiles.rules = [
      "d /var/lib/homelab-health 0755 root root -"
    ];

        systemd.services.homelab-health-report = {
      description = "Deterministic homelab health report";
      serviceConfig.Type = "oneshot";
      script = ''
        set -euo pipefail
        mkdir -p "$(dirname ${lib.escapeShellArg cfg.reportPath})"
        ${report}/bin/homelab-health | tee ${lib.escapeShellArg cfg.reportPath}
        chgrp hermes ${lib.escapeShellArg cfg.reportPath} || true
        chmod 0640 ${lib.escapeShellArg cfg.reportPath} || true
      '';
    };

    systemd.timers.homelab-health-report = {
      description = "Run the homelab health report daily";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        Unit = "homelab-health-report.service";
      };
    };
  };
}
