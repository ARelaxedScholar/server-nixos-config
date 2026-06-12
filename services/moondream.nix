{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.moondream;
in
{
  options.services.moondream = {
    enable = lib.mkEnableOption "Moondream captioning model (via Ollama)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.ollama;
      defaultText = lib.literalExpression "pkgs.ollama";
      description = "Ollama package to use for serving Moondream";
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "moondream";
      description = ''
        Ollama model tag to pull and serve.
        Defaults to "moondream" which is what swagwatch-engine expects.
      '';
      example = "moondream:latest";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 11434;
      description = "Port for the Ollama API server (engine hardcodes 11434)";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Bind address";
    };

    modelDir = lib.mkOption {
      type = lib.types.path;
      default = "/persist/cache/ollama";
      description = "Directory where Ollama stores downloaded models";
    };

    keepAlive = lib.mkOption {
      type = lib.types.str;
      default = "5m";
      description = ''
        How long to keep the model loaded in memory after last use.
        "5m" means 5 minutes; "24h" for always-hot; "0" for unload immediately.
      '';
      example = "24h";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "user";
      description = "System user to run the Ollama server as";
    };

    extraEnv = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Additional environment variables for the ollama server";
      example = {
        OLLAMA_NUM_PARALLEL = "4";
        OLLAMA_MAX_LOADED_MODELS = "2";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Model storage directory — already under /persist/cache which is persisted
    systemd.tmpfiles.rules = [
      "d ${cfg.modelDir} 0755 ${cfg.user} users -"
    ];

    systemd.services.moondream = {
      description = "Moondream captioning model server (Ollama)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      environment = {
        OLLAMA_HOST = "${cfg.host}:${toString cfg.port}";
        OLLAMA_MODELS = cfg.modelDir;
        OLLAMA_KEEP_ALIVE = cfg.keepAlive;
      }
      // cfg.extraEnv;

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Restart = "always";
        RestartSec = "10s";
        MemoryMax = "6G";

        ExecStart = "${cfg.package}/bin/ollama serve";

        # Pre-pull the Moondream model on first start so the engine
        # never waits for a download when it submits a caption job.
        ExecStartPre = "${cfg.package}/bin/ollama pull ${cfg.model}";
      };
    };
  };
}
