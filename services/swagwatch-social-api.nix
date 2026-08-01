{ pkgs, swagwatch-social-api, ... }:

let
  dataDir = "/mnt/data/swagwatch-social";
  imageDir = "${dataDir}/images";
  vtoImageDir = "${dataDir}/vto-images";
  envFile = "/persist/etc/secrets/swagwatch-social.env";
in
{
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 user users - -"
    "d ${imageDir} 0750 user users - -"
    "d ${vtoImageDir} 0750 user users - -"
  ];

  systemd.services.swagwatch-social-api = {
    description = "SwagWatch Social API";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "postgresql.service"
      "remote-engine.service"
    ];
    requires = [ "postgresql.service" ];
    wants = [
      "network-online.target"
      "remote-engine.service"
    ];
    unitConfig.ConditionPathExists = envFile;

    environment = {
      RUST_ENV = "production";
      SERVER_HOST = "127.0.0.1";
      SERVER_PORT = "3003";
      PUBLIC_URL = "https://api.swagwatch.app";
      CORS_ALLOWED_ORIGIN = "https://swagwatch.app";
      ENGINE_URL = "http://127.0.0.1:3001";
      LOCAL_IMAGE_STORE_PATH = imageDir;
      LOCAL_VTO_IMAGE_STORE_PATH = vtoImageDir;
      RUST_LOG = "swagwatch=info,sqlx=warn";
      LOG_FORMAT = "json";
    };

    serviceConfig = {
      Type = "simple";
      User = "user";
      Group = "users";
      EnvironmentFile = envFile;
      ExecStart = "${swagwatch-social-api.packages.x86_64-linux.default}/bin/swagwatch";
      Restart = "always";
      RestartSec = "5s";
      TimeoutStartSec = "2min";
      TimeoutStopSec = "30s";

      MemoryHigh = "768M";
      MemoryMax = "1536M";
      CPUWeight = 400;
      IOWeight = 100;
      LimitNOFILE = 65536;

      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ dataDir ];
      RestrictSUIDSGID = true;
    };
  };
}
