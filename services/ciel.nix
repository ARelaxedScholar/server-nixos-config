{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.services.ciel;
  cielPkg = inputs.ciel.packages.x86_64-linux.ciel;
  # Python with data science stack so the agent can backtest instead of
  # spending turns installing packages (server has no pip).
  pythonPkg = pkgs.python3.withPackages (ps: [
    ps.pandas
    ps.numpy
    ps.scipy
    ps.pip
  ]);
in
{
  options.services.ciel = {
    enable = lib.mkEnableOption "Ciel — Uriel evolved, 24/7 autonomous agent on the pi SDK";

    manageUser = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to create/manage the service user and group";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "ciel";
      description = "System user for the Ciel service";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "ciel";
      description = "System group for the Ciel service";
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/ciel";
      description = "State directory for database, sessions, and workspace";
    };

    envFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Path to a .env file with API keys and configuration.
        Required: DISCORD_BOT_TOKEN, DISCORD_CHANNEL_ID, DISCORD_OPERATOR_USER_ID
        Optional: CIEL_MODEL, CIEL_THINKING, SEARXNG_URL, TAVILY_API_KEY, BRIEFING_HOUR
      '';
      example = "/persist/etc/secrets/ciel.env";
    };

    soulFile = lib.mkOption {
      type = lib.types.str;
      description = "Path to soul.md (Ciel's immutable identity document)";
      example = "/persist/etc/secrets/soul.md";
    };

    agentDir = lib.mkOption {
      type = lib.types.str;
      default = "/persist/etc/secrets/ciel-agent";
      description = ''
        pi agent config dir holding auth.json (provider credentials) and
        optionally models.json. The daemon reads it via PI_CODING_AGENT_DIR.
      '';
      example = "/persist/etc/secrets/ciel-agent";
    };

    extraEnv = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Additional environment variables for the Ciel service";
      example = {
        CIEL_IDLE_TICK_SECS = "30";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    users = lib.mkIf cfg.manageUser {
      users.${cfg.user} = {
        isSystemUser = true;
        group = cfg.group;
        description = "Ciel autonomous agent service user";
        home = cfg.stateDir;
        createHome = true;
      };
      groups.${cfg.group} = { };
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0755 ${cfg.user} ${cfg.group} -"
      "d ${cfg.stateDir}/workspace 0755 ${cfg.user} ${cfg.group} -"
    ];

    systemd.services.ciel = {
      description = "Ciel — Uriel evolved, 24/7 autonomous agent";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      environment = {
        CIEL_SOUL_PATH = cfg.soulFile;
        CIEL_DB = "${cfg.stateDir}/workspace/ciel.db";
        CIEL_SESSION_DIR = "${cfg.stateDir}/workspace/sessions";
        PI_CODING_AGENT_DIR = cfg.agentDir;
        # pi's bash tool spawns sh; systemd default service PATH has none of
        # the tools the agent needs (python3, curl, git, ...).
        PATH = lib.mkForce "${pythonPkg}/bin:/usr/local/bin:/run/current-system/sw/bin:${pkgs.coreutils}/bin:${pkgs.bash}/bin:${pkgs.python3}/bin";
      }
      // cfg.extraEnv;

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${cielPkg}/bin/ciel";
        WorkingDirectory = cfg.stateDir;
        Restart = "on-failure";
        RestartSec = "10s";
        MemoryMax = "2G";
        EnvironmentFile = lib.mkIf (cfg.envFile != null) cfg.envFile;
      };
    };
  };
}
