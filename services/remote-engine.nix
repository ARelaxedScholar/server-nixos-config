{ pkgs, ... }:

let
  engineFlakePath = "/mnt/data/swagwatch-engine";
  vaultDir = "${engineFlakePath}/vault";
  envFile = "/persist/etc/secrets/remote-engine.env";
in
{
  systemd.services.remote-engine = {
    description = "SwagWatch Remote Engine";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig.ConditionPathExists = envFile;

    environment = {
      SERVER_HOST = "127.0.0.1";
      SERVER_PORT = "3001";
      VAULT_PATH = vaultDir;
      SOLVER_URL = "http://127.0.0.1:8000";
      QDRANT_URL = "http://127.0.0.1:6333";
      QDRANT_COLLECTION = "swagwatch_index";
      PUBLIC_BASE_URL = "https://engine.swagwatch.app";
      RUST_LOG = "swagwatch_engine=info,sqlx=warn,qdrant_client=warn";
      COOKIE_HARVESTER_SCRIPT_PATH = "${engineFlakePath}/scripts/harvest-cookies.js";
    };

    path = with pkgs;[ nodejs_22 chromium which ];

    serviceConfig = {
      Type = "simple";
      User = "user";
      Group = "users";
      EnvironmentFile = envFile;
      WorkingDirectory = engineFlakePath;
      ExecStart = "${pkgs.nix}/bin/nix run git+file://${engineFlakePath}#default";
      Restart = "always";
      RestartSec = "5s";
    };
  };
}
