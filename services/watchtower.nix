{ pkgs, watchtower, lib, config, ... }:
let
  cfg = config.services.watchtower;
in
{
  options.services.watchtower = {
    enable = lib.mkEnableOption "SwagWatch Watchtower ops control plane";
    package = lib.mkOption {
      type = lib.types.package;
      description = "Watchtower package to use";
      default = watchtower.packages.x86_64-linux.default;
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = "watchtower";
      description = "User to run watchtower as";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = "watchtower";
      description = "Group to run watchtower as";
    };
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/watchtower";
      description = "Working/state directory for watchtower";
    };
    bind = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:8080";
      description = "Listen address for the watchtower API";
    };
    envFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to an EnvironmentFile with secrets (not tracked in git). Should set at
        least DATABASE_URL and WATCHTOWER_CONFIG, plus any optional integration
        tokens (GITHUB_TOKEN, HERMES_GATEWAY_URL, HERMES_AUTH_TOKEN, WATCHTOWER_TELEGRAM_*).
        For local peer auth use: DATABASE_URL=postgres:///watchtower?host=/run/postgresql
      '';
      example = "/persist/etc/secrets/watchtower.env";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      description = "Watchtower service user";
      home = cfg.dataDir;
      createHome = true;
    };
    users.groups.${cfg.group} = { };

    systemd.services.watchtower = {
      description = "SwagWatch Watchtower - Internal Ops Control Plane";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "postgresql.service"
      ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = lib.getExe cfg.package;
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;
        Restart = "on-failure";
        RestartSec = "5s";
        EnvironmentFile = cfg.envFile;
        Environment = [
          "WATCHTOWER_BIND=${cfg.bind}"
        ];
        # Security hardening (mirrors the upstream deploy unit).
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.dataDir ];
      };
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} -"
    ];
  };
}
