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
 memoryProvider = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "honcho";
      description = "External memory provider to configure for Hermes (honcho, mem0, etc.), or null to leave disabled";
    };

    honchoBaseUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Base URL for a self-hosted Honcho instance";
      example = "http://honcho.local:8787";
    };

    honchoApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Optional file containing the self-hosted Honcho bearer/JWT token";
      example = "/persist/etc/secrets/honcho-token";
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

    stateImportFrom = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Optional source directory to seed the Hermes home from on first boot.
        Use this to migrate an existing interactive home into the service home
        for continuity (for example /home/user/.hermes).
      '';
      example = "/home/user/.hermes";
    };

    kanban = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = ''
        Kanban board configuration merged into config.yaml.
        Example: { orchestrator_profile = "default"; default_assignee = "default"; }
      '';
    };

    kanbanDecomposer = lib.mkOption {
      type = lib.types.nullOr lib.types.attrs;
      default = null;
      description = ''
        Auxiliary model config for the kanban decomposer.
        Example: { provider = "deepseek"; model = "deepseek-v4-flash"; api_key = "sk-..."; }
      '';
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


    systemd.tmpfiles.rules = lib.optionals cfg.manageUser [
      "d ${cfg.stateDir} 0755 ${cfg.user} ${cfg.group} -"
      "z ${cfg.stateDir} 0755 ${cfg.user} ${cfg.group} -"
      # z = set perms on existing dirs too (impermanence can leave stale 0700)
      "z ${cfg.stateDir}/.hermes 2775 ${cfg.user} ${cfg.group} -"
      "d ${cfg.stateDir}/workspace 0755 ${cfg.user} ${cfg.group} -"
      "d ${cfg.stateDir}/workspace/server-nixos-config 0755 ${cfg.user} ${cfg.group} -"
      # Fix ownership of stale root-owned files after rebuild
      "z ${cfg.stateDir}/.hermes/config.yaml 0640 ${cfg.user} ${cfg.group} -"
      "z ${cfg.stateDir}/.hermes/gateway.lock 0640 ${cfg.user} ${cfg.group} -"
      "z ${cfg.stateDir}/.hermes/gateway.pid 0640 ${cfg.user} ${cfg.group} -"
    ];

    systemd.services.hermes-seed-state = lib.mkIf (cfg.stateImportFrom != null) {
      description = "Seed Hermes state from existing home";
      wantedBy = [ "hermes-init-config.service" ];
      before = [ "hermes-init-config.service" ];
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        set -euo pipefail
        SRC="${toString cfg.stateImportFrom}"
        DST="${cfg.stateDir}/.hermes"
        MARKER="$DST/.seeded-from-global"

        if [ -e "$MARKER" ]; then
          exit 0
        fi

        if [ ! -d "$SRC" ]; then
          echo "Seed source $SRC does not exist; skipping"
          exit 0
        fi

        install -d -m 0700 -o ${cfg.user} -g ${cfg.group} "$DST"
        ${pkgs.rsync}/bin/rsync -a \
          --exclude='*.lock' \
          --exclude='gateway.pid' \
          "$SRC"/ "$DST"/
        chown -R ${cfg.user}:${cfg.group} "$DST"
        rm -f "$DST/auth.lock" "$DST/gateway.lock" "$DST/gateway.pid" "$DST/kanban.db.init.lock"
        touch "$MARKER"
        chown ${cfg.user}:${cfg.group} "$MARKER"
      '';
    };

    # Generate config.yaml from declarative settings
    systemd.services.hermes-init-config = {
      description = "Initialize Hermes Agent config";
      requiredBy = [ "hermes-agent.service" ];
      after = [ "hermes-seed-state.service" ];
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

        # Generate config.yaml if it doesn't exist (never overwrite)
        if [ ! -f "$HERMES_HOME/config.yaml" ]; then
          ${hermesPkg}/bin/hermes config --init 2>/dev/null || true
        fi

        # Merge env file — only seed if .env doesn't already exist
        if [ -n "${cfg.envFile}" ] && [ -f "${cfg.envFile}" ]; then
          if [ "${cfg.envFile}" != "$HERMES_HOME/.env" ] && [ ! -f "$HERMES_HOME/.env" ]; then
            install -m 0664 "${cfg.envFile}" "$HERMES_HOME/.env"
          fi
        fi

        # Write honcho.json only if it doesn't exist (never overwrite user config)
        if [ "${if cfg.memoryProvider != null then cfg.memoryProvider else ""}" = "honcho" ] && [ ! -f "$HERMES_HOME/honcho.json" ]; then
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

        # Ensure $HERMES_HOME itself is owned and traversable by Hermes
        install -d -m 0700 -o ${cfg.user} -g ${cfg.group} "$HERMES_HOME"

        # Ensure config.yaml is owned by Hermes, readable only by user+group (non-recursive, non-group-write)
        chown ${cfg.user}:${cfg.group} "$HERMES_HOME/config.yaml" 2>/dev/null || true
        chmod 0640 "$HERMES_HOME/config.yaml" 2>/dev/null || true
      '';
    };

    # Apply kanban + decomposer config declaratively (runs after init-config)
    systemd.services.hermes-kanban-config = lib.mkIf (cfg.kanban != {} || cfg.kanbanDecomposer != null) {
      description = "Apply kanban board configuration to Hermes config.yaml";
      requiredBy = [ "hermes-agent.service" ];
      after = [ "hermes-init-config.service" ];
      before = [ "hermes-agent.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
      };
      script = let
        kd = cfg.kanbanDecomposer;
        triageCfg = lib.optionalString (kd != null && kd.provider != null) ''
          ${hermesPkg}/bin/hermes config set auxiliary.triage_specifier.provider ${toString kd.provider}
          ${hermesPkg}/bin/hermes config set auxiliary.triage_specifier.model ${toString (kd.model or "")}
          ${hermesPkg}/bin/hermes config set auxiliary.triage_specifier.base_url ${toString (kd.base_url or "")}
        '' + lib.optionalString (kd != null && kd.api_key_env != null) ''
          ${hermesPkg}/bin/hermes config set auxiliary.triage_specifier.api_key_env ${toString kd.api_key_env}
        '';
        decompCfg = lib.optionalString (kd != null) (
          (lib.optionalString (kd.provider != null) ''
            ${hermesPkg}/bin/hermes config set auxiliary.kanban_decomposer.provider ${toString kd.provider}
          '') +
          (lib.optionalString (kd.model != null) ''
            ${hermesPkg}/bin/hermes config set auxiliary.kanban_decomposer.model ${toString kd.model}
          '') +
          (lib.optionalString (kd.base_url != null) ''
            ${hermesPkg}/bin/hermes config set auxiliary.kanban_decomposer.base_url ${toString kd.base_url}
          '') +
          (lib.optionalString (kd.api_key_env != null) ''
            ${hermesPkg}/bin/hermes config set auxiliary.kanban_decomposer.api_key_env ${toString kd.api_key_env}
          '') +
          (lib.optionalString (kd.api_key != null) ''
            ${hermesPkg}/bin/hermes config set auxiliary.kanban_decomposer.api_key ${toString kd.api_key}
          '')
        );
      in ''
        HERMES_HOME="${cfg.stateDir}/.hermes"
        export HERMES_HOME
        ${hermesPkg}/bin/hermes config set kanban.orchestrator_profile ${toString (cfg.kanban.orchestrator_profile or "")}
        ${hermesPkg}/bin/hermes config set kanban.dispatch_in_gateway ${lib.boolToString (cfg.kanban.dispatch_in_gateway or true)}
        ${hermesPkg}/bin/hermes config set kanban.auto_decompose ${lib.boolToString (cfg.kanban.auto_decompose or true)}
        ${hermesPkg}/bin/hermes config set kanban.failure_limit ${toString (cfg.kanban.failure_limit or 2)}
      '' + decompCfg + triageCfg;
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
        ExecStart = "${hermesPkg}/bin/hermes gateway run --replace";
        WorkingDirectory = "${cfg.stateDir}/workspace";
        Restart = "on-failure";
        RestartSec = "15s";
        StartLimitIntervalSec = 300;
        StartLimitBurst = 5;
      };
    };

    # Web dashboard for kanban board, sessions, config
    systemd.services.hermes-dashboard = {
      description = "Hermes Agent Web Dashboard";
      wantedBy = [ "multi-user.target" ];
      after = [ "hermes-agent.service" ];
      requires = [ "hermes-agent.service" ];

      environment.HERMES_HOME = "${cfg.stateDir}/.hermes";

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${hermesPkg}/bin/hermes dashboard --port 9119 --host 127.0.0.1 --no-open";
        WorkingDirectory = "${cfg.stateDir}/workspace";
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };

  };
}
