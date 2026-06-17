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

    manageUser = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether this module should create/manage the service user and group";
    };

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
    users = lib.mkIf cfg.manageUser {
      users.${cfg.user} = {
        isSystemUser = true;
        group = cfg.group;
        description = "Hermes Agent service user";
        home = "${cfg.stateDir}/home";
        createHome = true;
      };
      groups.${cfg.group} = { };
    };

    # Make hermes CLI available on PATH
    environment.systemPackages = [ hermesPkg ];

    # Set HERMES_HOME system-wide so CLI shares state with the service
    environment.sessionVariables = {
      HERMES_HOME = "${cfg.stateDir}/.hermes";
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0755 ${cfg.user} ${cfg.group} -"
      "z ${cfg.stateDir} 0755 ${cfg.user} ${cfg.group} -"
      # z = set perms on existing dirs too (impermanence can leave stale 0700)
      "z ${cfg.stateDir}/.hermes 2775 ${cfg.user} ${cfg.group} -"
      "d ${cfg.stateDir}/workspace 0755 ${cfg.user} ${cfg.group} -"
      "d ${cfg.stateDir}/workspace/server-nixos-config 0755 ${cfg.user} ${cfg.group} -"
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
          if [ "${cfg.envFile}" != "$HERMES_HOME/.env" ]; then
            # install removes old file first so owner is always hermes
            install -m 0664 "${cfg.envFile}" "$HERMES_HOME/.env"
          fi
        fi

        if [ "${if cfg.memoryProvider != null then cfg.memoryProvider else ""}" = "honcho" ]; then
          mkdir -p "$HERMES_HOME"
          cat > "$HERMES_HOME/honcho.json" <<EOF
{
  "hosts": {
    "self-hosted": {
      "baseUrl": "${if cfg.honchoBaseUrl != null then cfg.honchoBaseUrl else "http://127.0.0.1:8787"}"
    }
  }
}
EOF
          if [ -n "${if cfg.honchoApiKeyFile != null then toString cfg.honchoApiKeyFile else ""}" ] && [ -f "${if cfg.honchoApiKeyFile != null then toString cfg.honchoApiKeyFile else "/dev/null"}" ]; then
            token="$(${pkgs.coreutils}/bin/cat ${toString cfg.honchoApiKeyFile})"
            ${pkgs.jq}/bin/jq --arg token "$token" '.hosts["self-hosted"].apiKey = $token' "$HERMES_HOME/honcho.json" > "$HERMES_HOME/honcho.json.tmp"
            mv "$HERMES_HOME/honcho.json.tmp" "$HERMES_HOME/honcho.json"
          fi
        fi

        # Fix perms — must run AFTER hermes config --init, which
        # recreates .hermes with 0700. Impermanence also preserves
        # stale perms across reboots.
        # 2775: setgid so new children inherit the hermes group
        find "$HERMES_HOME" -type d -exec chmod 2775 {} + || true
        find "$HERMES_HOME" -type f -exec chmod 0664 {} + || true
      '';
    };

    systemd.services.hermes-memory-setup = {
      description = "Configure Hermes memory provider";
      requiredBy = [ "hermes-init-config.service" ];
      before = [ "hermes-init-config.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
      };
      script = ''
        HERMES_HOME="${cfg.stateDir}/.hermes"
        export HERMES_HOME
        mkdir -p "$HERMES_HOME"
        if [ "${if cfg.memoryProvider != null then cfg.memoryProvider else ""}" = "honcho" ]; then
          cat > "$HERMES_HOME/config.yaml" <<EOF
memory:
  provider: honcho
EOF
        fi
      '';
    };

    systemd.services.hermes-workspace-perms = {
      description = "Ensure Hermes workspace permissions and git trust";
      requiredBy = [ "hermes-agent.service" ];
      before = [ "hermes-agent.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
      };
      script = ''
        install -d -m 0755 -o ${cfg.user} -g ${cfg.group} ${cfg.stateDir}/workspace/server-nixos-config
        ${pkgs.git}/bin/git config --global --add safe.directory ${cfg.stateDir}/workspace/server-nixos-config || true
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

      environment.HERMES_HOME = "${cfg.stateDir}/.hermes";

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${hermesPkg}/bin/hermes gateway run";
        WorkingDirectory = "${cfg.stateDir}/workspace";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

  };
}
