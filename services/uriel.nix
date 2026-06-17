{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.services.uriel;
  urielPkg = inputs.uriel.packages.x86_64-linux.uriel;
in
{
  options.services.uriel = {
    enable = lib.mkEnableOption "Uriel — 24/7 autonomous agent";

    manageUser = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to create/manage the service user and group";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "uriel";
      description = "System user for the Uriel service";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "uriel";
      description = "System group for the Uriel service";
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/uriel";
      description = "State directory for database, streams, and workspace";
    };

    envFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a .env file with API keys and configuration.
        Required: NVIDIA_API_KEY, DISCORD_BOT_TOKEN, DISCORD_CHANNEL_ID, DISCORD_OPERATOR_USER_ID
        Optional: TAVILY_API_KEY, OLLAMA_HOST, OLLAMA_MODEL, NIM_MODEL_HEAVY, NIM_MODEL_LIGHT
      '';
      example = "/persist/etc/secrets/uriel.env";
    };

    soulFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to soul.md (Uriel's immutable identity document)";
      example = "/persist/etc/secrets/uriel-soul.md";
    };

    sys1Stub = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Run with Sys1Stub (always returns Ignore) instead of connecting to Ollama.
        Intended for soak testing and environments without a local model.
        When true, no Ollama instance is required.
      '';
    };

    extraEnv = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Additional environment variables for the Uriel service";
      example = {
        RUST_LOG = "info,uriel=debug";
        TICK_INTERVAL_SECS = "30";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    users = lib.mkIf cfg.manageUser {
      users.${cfg.user} = {
        isSystemUser = true;
        group = cfg.group;
        description = "Uriel autonomous agent service user";
        home = cfg.stateDir;
        createHome = true;
      };
      groups.${cfg.group} = { };
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0755 ${cfg.user} ${cfg.group} -"
      "d ${cfg.stateDir}/workspace 0755 ${cfg.user} ${cfg.group} -"
      "d ${cfg.stateDir}/workspace/streams 0755 ${cfg.user} ${cfg.group} -"
      "d ${cfg.stateDir}/workspace/state 0755 ${cfg.user} ${cfg.group} -"
      "d ${cfg.stateDir}/workspace/state-snapshots 0755 ${cfg.user} ${cfg.group} -"
    ];

    systemd.services.uriel = {
      description = "Uriel — 24/7 autonomous agent";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
      ];
      wants = [ "network-online.target" ];

      environment = {
        SOUL_PATH = cfg.soulFile;
        DATABASE_URL = "sqlite:${cfg.stateDir}/workspace/memory.db";
        STREAM_DIR = "${cfg.stateDir}/workspace/streams";
        WORKSPACE_DIR = "${cfg.stateDir}/workspace";
        ACTIVE_STREAM_FILE = "${cfg.stateDir}/workspace/streams/stream_001.log";
        RUST_LOG = "info,uriel=debug";
      }
      // (lib.optionalAttrs cfg.sys1Stub {
        SYS1_STUB = "1";
      })
      // cfg.extraEnv;

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${urielPkg}/bin/uriel";
        WorkingDirectory = cfg.stateDir;
        Restart = "on-failure";
        RestartSec = "10s";
        MemoryMax = "2G";
        EnvironmentFile = lib.mkIf (cfg.envFile != null) cfg.envFile;
      };
    };
  };
}
