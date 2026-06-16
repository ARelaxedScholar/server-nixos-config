{
  config,
  lib,
  pkgs,
  hermes-agent,
  ...
}:
let
  cfg = config.services.hermes;
in
{
  imports = [
    hermes-agent.nixosModules.default
  ];

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
  };

  config = lib.mkIf cfg.enable {
    services.hermes-agent = {
      enable = true;
      addToSystemPackages = true;
      settings.model.default = cfg.model;
      environmentFiles = lib.optional (cfg.envFile != null) cfg.envFile;
    };
  };
}
