{
  pkgs,
  lib,
  config,
  forge,
  ...
}:
let
  cfg = config.services.forge;
  forgePkg = forge.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  options.services.forge = {
    enable = lib.mkEnableOption "Forge recoverable MLOps orchestration framework";

    package = lib.mkOption {
      type = lib.types.package;
      default = forgePkg;
      description = "Forge package to run.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "forge";
      description = "User to run Forge maintenance jobs as.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "forge";
      description = "Group to run Forge maintenance jobs as.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/forge";
      description = "Forge persistent state directory.";
    };

    runsDir = lib.mkOption {
      type = lib.types.path;
      default = "${cfg.dataDir}/runs";
      description = "Forge run directories.";
    };

    ledger = lib.mkOption {
      type = lib.types.path;
      default = "${cfg.dataDir}/ledger.sqlite";
      description = "Forge SQLite ledger path.";
    };

    vastaiEnvFile = lib.mkOption {
      type = lib.types.path;
      default = "/persist/etc/secrets/vastai.env";
      description = "EnvironmentFile containing VAST_API_KEY for Vast.ai non-spending checks and reaper.";
    };

    reaper = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable the Forge orphaned Vast instance reaper timer.";
      };

      dryRun = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run the reaper in dry-run mode. Keep true until the Section 18 safety gate passes.";
      };

      interval = lib.mkOption {
        type = lib.types.str;
        default = "10min";
        description = "OnUnitActiveSec interval for the Forge reaper timer.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      description = "Forge MLOps orchestration service user";
      home = cfg.dataDir;
      createHome = true;
    };
    users.groups.${cfg.group} = { };

    environment.systemPackages = [ cfg.package ];

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.runsDir} 0750 ${cfg.user} ${cfg.group} -"
      # Let the non-root Forge reaper traverse the secrets directory and read
      # only the Vast env file it needs.  Do not relax ownership/mode for the
      # whole secrets tree.
      "a+ /persist/etc/secrets - - - - g:${cfg.group}:--x"
      "a+ ${cfg.vastaiEnvFile} - - - - g:${cfg.group}:r--"
    ];

    systemd.services.forge-reaper = lib.mkIf cfg.reaper.enable {
      description = "Forge orphaned Vast GPU instance reaper";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      unitConfig.OnFailure = [ "notify-failure@%p.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.dataDir;
        EnvironmentFile = cfg.vastaiEnvFile;
        Environment = [
          "FORGE_RUNS_DIR=${cfg.runsDir}"
          "FORGE_LEDGER=${cfg.ledger}"
          "VASTAI_ENV=${cfg.vastaiEnvFile}"
        ];
        ExecStart = "${cfg.package}/bin/forge reap-orphans --real-vast${lib.optionalString cfg.reaper.dryRun " --dry-run"}";
        StandardOutput = "journal";
        StandardError = "journal";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.dataDir ];
        TimeoutStartSec = "60s";
        CPUQuota = "20%";
        MemoryMax = "256M";
      };
    };

    systemd.timers.forge-reaper = lib.mkIf cfg.reaper.enable {
      description = "Run Forge orphaned Vast GPU instance reaper periodically";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = cfg.reaper.interval;
        AccuracySec = "30s";
        Persistent = true;
        Unit = "forge-reaper.service";
      };
    };
  };
}
