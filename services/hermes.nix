{
  config,
  lib,
  pkgs,
  llm-agents,
  ...
}:
let
  cfg = config.services.hermes;
  hermesPkg = llm-agents.packages.x86_64-linux.hermes-agent;
in
{
  options.services.hermes = {
    enable = lib.mkEnableOption "Hermes Agent (Nous Research autonomous agent framework)";

    envFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a .env file with API keys.
        At minimum: OPENROUTER_API_KEY=sk-or-...
        Or for direct Anthropic: ANTHROPIC_API_KEY=sk-ant-...
      '';
      example = "/persist/etc/secrets/hermes.env";
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "anthropic/claude-sonnet-4";
      description = "Default LLM model identifier (as your provider expects it)";
      example = "anthropic/claude-sonnet-4";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "hermes";
      description = "System user for the hermes-agent";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "hermes";
      description = "System group for the hermes-agent";
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/hermes";
      description = "State directory (HERMES_HOME)";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      description = "Hermes Agent service user";
      home = cfg.stateDir;
      createHome = true;
    };
    users.groups.${cfg.group} = { };

    # Make hermes CLI available on PATH
    environment.systemPackages = [ hermesPkg ];

    # Set HERMES_HOME system-wide so CLI shares state with the service
    environment.sessionVariables = {
      HERMES_HOME = "${cfg.stateDir}/.hermes";
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0755 ${cfg.user} ${cfg.group} -"
      "d ${cfg.stateDir}/.hermes 0755 ${cfg.user} ${cfg.group} -"
      "d ${cfg.stateDir}/workspace 0755 ${cfg.user} ${cfg.group} -"
      "d ${cfg.stateDir}/home 0755 ${cfg.user} ${cfg.group} -"
    ];

    # Generate config.yaml from declarative settings
    systemd.services.hermes-init-config = {
      description = "Initialize Hermes Agent config";
      requiredBy = [ "hermes-agent.service" ];
      before = [ "hermes-agent.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
      };
      script = ''
        HERMES_HOME="${cfg.stateDir}/.hermes"
        export HERMES_HOME

        mkdir -p "$HERMES_HOME"

        # Generate config.yaml if it doesn't exist
        if [ ! -f "$HERMES_HOME/config.yaml" ]; then
          ${hermesPkg}/bin/hermes config --init 2>/dev/null || true
        fi

        # Merge env file
        if [ -n "${cfg.envFile}" ] && [ -f "${cfg.envFile}" ]; then
          cp "${cfg.envFile}" "$HERMES_HOME/.env"
          chmod 0600 "$HERMES_HOME/.env"
        fi
      '';
    };

    systemd.services.hermes-agent = {
      description = "Hermes Agent - Nous Research autonomous agent framework";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network-online.target"
        "hermes-init-config.service"
      ];
      wants = [ "network-online.target" ];
      requires = [ "hermes-init-config.service" ];

      environment = {
        HERMES_HOME = "${cfg.stateDir}/.hermes";
        HERMES_MANAGED = "true";
      };

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${hermesPkg}/bin/hermes gateway run";
        WorkingDirectory = "${cfg.stateDir}/workspace";
        Restart = "on-failure";
        RestartSec = "5s";
        MemoryMax = "4G";
        # Hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = [ cfg.stateDir ] ++ lib.optional (cfg.envFile != null) cfg.envFile;
      };
    };

  };
}
