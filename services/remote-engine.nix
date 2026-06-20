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

      # Scraping throughput knobs.  Product concurrency widens the ingestion
      # worker's per-collection processing windows. Scheduler knobs let the
      # due-target backlog drain on a daily cadence instead of being capped at
      # 100 claims per 5-minute tick. The Redis-backed DistributedRateLimiter
      # still gates per-domain request rate.
      DEFAULT_SCRAPER_CONCURRENCY = "40";
      SCRAPER_CONCURRENCY = "ssense.com:64,kith.com:48,aritzia.com:48,urban-planet.com:48,simons.ca:24,target.com:16";
      # Redis token-bucket limits: domain:burst_capacity:refill_per_second.
      # Suffix matching is supported, so asos.com also covers www.asos.com.
      SCRAPER_RATE_LIMITS = "asos.com:50:20,massimodutti.com:20:5,bershka.com:20:5,stradivarius.com:20:5,pullandbear.com:20:5,zara.com:20:5,oysho.com:20:5,kith.com:5:1.5";
      SCRAPE_DISCOVERY_CONCURRENCY = "16";
      SCRAPE_DOMAIN_CONCURRENCY = "20";
      SCRAPE_TARGETS_PER_DOMAIN_CONCURRENCY = "4";
      SCRAPE_CLAIM_BATCH_SIZE = "2000";
      SCRAPE_CLAIM_LEASE_HOURS = "2";

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
      # Give the scraper breathing room, but protect the 32GB host. Redis was
      # previously carrying multi-GB scheduler queues; after trimming that,
      # the engine can safely have more headroom for wider scrape batches.
      MemoryHigh = "12G"; # Start throttling here
      MemoryMax = "16G"; # Absolute kill limit

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
