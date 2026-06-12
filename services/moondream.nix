{ config, lib, pkgs, ... }:

let
  cfg = config.services.moondream;
in
{
  options.services.moondream = {
    enable = lib.mkEnableOption "Moondream captioning model via llama.cpp";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.llama-cpp;
      defaultText = lib.literalExpression "pkgs.llama-cpp";
      description = "llama.cpp package to use for serving Moondream";
    };

    hfRepo = lib.mkOption {
      type = lib.types.str;
      default = "moondream/moondream2-gguf:Q4_K_M";
      description = ''
        Hugging Face model repository for the Moondream GGUF model.
        Format: <user>/<model>[:quant] (e.g., "moondream/moondream2-gguf:Q4_K_M")
      '';
      example = "moondream/moondream2-gguf:Q8_0";
    };

    hfFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Specific Hugging Face model file name. If set, overrides the quant
        suffix in hfRepo. Useful when the repo has non-standard filenames.
      '';
      example = "moondream2-Q4_K_M.gguf";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8002;
      description = "Port for the Moondream captioning API server";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Bind address (use 127.0.0.1 for local-only, 0.0.0.0 for network access)";
    };

    modelDir = lib.mkOption {
      type = lib.types.path;
      default = "/persist/cache/llama-models";
      description = "Directory to cache downloaded GGUF models in";
    };

    contextSize = lib.mkOption {
      type = lib.types.ints.positive;
      default = 8192;
      description = "Context size (--ctx-size) for the model";
    };

    layers = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 99;
      description = "Number of layers to offload to GPU (-ngl). 99 = all layers";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional arguments passed directly to llama-server";
      example = [ "--no-mmap" ];
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "user";
      description = "System user to run the Moondream server as";
    };
  };

  config = lib.mkIf cfg.enable {
    # Model cache directory persisted via impermanence
    systemd.tmpfiles.rules = [
      "d ${cfg.modelDir} 0755 ${cfg.user} users -"
    ];

    systemd.services.moondream = {
      description = "Moondream captioning model server (llama.cpp)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      # Tell llama.cpp where to cache downloaded models
      environment = {
        LLAMA_ARG_MODEL_DIR = cfg.modelDir;
      };

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Restart = "always";
        RestartSec = "10s";
        MemoryMax = "6G";

        ExecStart = lib.escapeShellArgs (
          [
            "${cfg.package}/bin/llama-server"
            "--hf-repo" cfg.hfRepo
            "--host" cfg.host
            "--port" (toString cfg.port)
            "--mmproj-auto"
            "--mlock"
            "-ngl" (toString cfg.layers)
            "-c" (toString cfg.contextSize)
          ] ++ lib.optionals (cfg.hfFile != null) [
            "--hf-file" cfg.hfFile
          ] ++ cfg.extraArgs
        );
      };
    };
  };
}
