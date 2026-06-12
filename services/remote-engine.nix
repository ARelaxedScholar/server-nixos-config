{ pkgs, swagwatch-engine, ... }:

let
  engineFlakePath = "/mnt/data/swagwatch-engine";
  vaultDir = "${engineFlakePath}/vault";
  envFile = "/persist/etc/secrets/remote-engine.env";
in
{
  systemd.services.remote-engine = {
    description = "SwagWatch Remote Engine";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "moondream.service"
    ];
    wants = [
      "network-online.target"
      "moondream.service"
    ];
    unitConfig.ConditionPathExists = envFile;

    environment = {
      SERVER_HOST = "127.0.0.1";
      SERVER_PORT = "3001";
      VAULT_PATH = vaultDir;
      SOLVER_URL = "http://127.0.0.1:8001";
      QDRANT_URL = "http://127.0.0.1:6333";
      QDRANT_COLLECTION = "swagwatch_index";
      PUBLIC_BASE_URL = "https://engine.swagwatch.app";
      RUST_LOG = "swagwatch_engine=info,sqlx=warn,qdrant_client=warn";
      REDIS_URL = "redis://127.0.0.1:6379";
      COOKIE_HARVESTER_SCRIPT_PATH = "${engineFlakePath}/scripts/harvest-cookies.js";
      # Tell the caption worker where to find Moondream (via Ollama)
      # Port 11434 is hardcoded in ollama.rs, hostname only here
      OLLAMA_HOST = "http://127.0.0.1";
    };

    path = with pkgs; [
      nodejs_22
      chromium
      which
      git
    ];

    serviceConfig = {
      Type = "simple";
      User = "user";
      Group = "users";

      # --- THE VIP RESOURCE BOUNDS ---
      # Give the scraper breathing room, but protect the 32GB host
      MemoryHigh = "8G"; # Start throttling here
      MemoryMax = "12G"; # Absolute kill limit

      # Priority: Negative 'Nice' means SwagWatch gets CPU priority over Animus
      Nice = -5;
      CPUSchedulingPolicy = "rr";

      # Disk Priority: Direct, high-speed access to the SSD
      IOWeight = 100;

      # File descriptor limit: bump from default 1024 to hard limit.
      # The engine's socket backlog is 4096, and scraping/discovery/search
      # concurrently consume many FDs. Without this, cloudflared gets
      # "connection refused" when the FD pool is exhausted.
      LimitNOFILE = 524288;

      # ENV
      EnvironmentFile = envFile;
      WorkingDirectory = engineFlakePath;
      ExecStart = "${swagwatch-engine.packages.x86_64-linux.default}/bin/swagwatch_engine";
      Restart = "always";
      RestartSec = "5s";
    };
  };
}
