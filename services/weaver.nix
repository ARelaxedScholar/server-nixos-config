{
  pkgs,
  weaver,
  lib,
  config,
  ...
}:
let
  cfg = config.services.weaver;

  # Build Weaver (pure-Python) from the GitLab source flake input. All runtime
  # deps are in nixpkgs, so no venv is needed at deploy time.
  weaverPkg = pkgs.python3Packages.buildPythonApplication {
    pname = "weaver";
    version = "0.1.0";
    src = weaver;
    pyproject = true;
    build-system = [ pkgs.python3Packages.setuptools ];
    nativeBuildInputs = [ pkgs.python3Packages.pythonRelaxDepsHook ];
    pythonRelaxDeps = [
      "pillow"
      "structlog"
    ];
    dependencies = with pkgs.python3Packages; [
      httpx
      pillow
      pydantic
      pydantic-settings
      structlog
      beautifulsoup4
    ];
    doCheck = false;
  };

  # A oneshot unit. Weaver reads config from the process environment
  # (pydantic-settings), so EnvironmentFile is sufficient — no .env on disk.
  mkService = description: args: {
    inherit description;
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
      User = cfg.user;
      Group = cfg.group;
      WorkingDirectory = cfg.dataDir;
      EnvironmentFile = cfg.envFile;
      ExecStart = "${cfg.package}/bin/weaver ${args}";
      StandardOutput = "journal";
      StandardError = "journal";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ cfg.dataDir ];
    };
  };

  mkTimer = description: onCalendar: randomizedDelaySec: {
    inherit description;
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = onCalendar;
      Persistent = true;
      RandomizedDelaySec = randomizedDelaySec;
    };
  };
in
{
  options.services.weaver = {
    enable = lib.mkEnableOption "Weaver SwagWatch growth bot";
    package = lib.mkOption {
      type = lib.types.package;
      default = weaverPkg;
      description = "Weaver package to use (built from source by default)";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = "weaver";
      description = "User to run weaver as";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = "weaver";
      description = "Group to run weaver as";
    };
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/weaver";
      description = "Working/state directory (state.json, content/ live here)";
    };
    envFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to an EnvironmentFile with secrets/config (not tracked in git):
        ENGINE_API_KEY, PINTEREST_*, LLM_API_KEY, and any LEADGEN_*/GRAPH_*
        settings. See weaver/.env.example for the full list.
      '';
      example = "/persist/etc/secrets/weaver.env";
    };
    pseoInterval = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 00,02,04,06,08,10,12,14,16,18,20,22:00:00";
      description = "OnCalendar schedule for the pSEO pin cycle (default: every 2h)";
    };
    enableIntelligence = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the daily B2B intelligence content-factory timer";
    };
    enableLeadgen = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the daily lead-gen (qualify + draft -> O365) timer";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      description = "Weaver service user";
      home = cfg.dataDir;
      createHome = true;
    };
    users.groups.${cfg.group} = { };

    systemd.services = lib.mkMerge [
      { "weaver-pseo" = mkService "Weaver - SwagWatch pSEO marketing bot (one-shot)" "--run-once"; }
      (lib.mkIf cfg.enableIntelligence {
        "weaver-intelligence" =
          mkService "Weaver Intelligence - B2B content factory (one-shot)" "--intelligence";
      })
      (lib.mkIf cfg.enableLeadgen {
        "weaver-leadgen" = mkService "Weaver Lead-gen - qualify + draft outreach (one-shot)" "--leadgen";
      })
    ];

    systemd.timers = lib.mkMerge [
      { "weaver-pseo" = mkTimer "Weaver pSEO - run on schedule" cfg.pseoInterval 60; }
      (lib.mkIf cfg.enableIntelligence {
        "weaver-intelligence" = mkTimer "Weaver Intelligence - daily" "daily" 3600;
      })
      (lib.mkIf cfg.enableLeadgen {
        "weaver-leadgen" = mkTimer "Weaver Lead-gen - daily" "daily" 3600;
      })
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} -"
    ];
  };
}
