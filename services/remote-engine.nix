{ pkgs, swagwatch-engine, ... }:

let
  engineFlakePath = "/mnt/data/swagwatch-engine";
  vaultDir = "${engineFlakePath}/vault";
  envFile = "/persist/etc/secrets/remote-engine.env";
  waitForQdrant = pkgs.writeShellScript "wait-for-qdrant" ''
    for attempt in $(${pkgs.coreutils}/bin/seq 1 180); do
      if ${pkgs.curl}/bin/curl --fail --silent --max-time 2 \
        http://127.0.0.1:6333/readyz > /dev/null; then
        exit 0
      fi
      ${pkgs.coreutils}/bin/sleep 2
    done

    echo "Qdrant did not become ready within 6 minutes" >&2
    exit 1
  '';
in
{
  systemd.services.remote-engine = {
    description = "SwagWatch Remote Engine";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "qdrant.service"
    ];
    requires = [ "qdrant.service" ];
    wants = [
      "network-online.target"
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

      # Keep acquisition broad enough to maintain freshness without allowing
      # scrape fan-out to exhaust the database pool or starve customer search.
      # Four domains with one active target each and eight product jobs per
      # target still permits roughly 32 concurrent product fetches.
      DEFAULT_SCRAPER_CONCURRENCY = "8";
      SCRAPER_CONCURRENCY = "ssense.com:12,kith.com:10,aritzia.com:10,urban-planet.com:10,simons.ca:6,target.com:4";
      # Redis token-bucket limits: domain:burst_capacity:refill_per_second.
      # Suffix matching is supported, so asos.com also covers www.asos.com.
      SCRAPER_RATE_LIMITS = "asos.com:50:20,massimodutti.com:20:5,bershka.com:20:5,stradivarius.com:20:5,pullandbear.com:20:5,zara.com:20:5,oysho.com:20:5,kith.com:5:1.5";
      SCRAPE_DISCOVERY_CONCURRENCY = "4";
      SCRAPE_DOMAIN_CONCURRENCY = "4";
      SCRAPE_TARGETS_PER_DOMAIN_CONCURRENCY = "1";
      SCRAPE_CLAIM_BATCH_SIZE = "2000";
      SCRAPE_CLAIM_LEASE_HOURS = "2";

      # Catalog discovery may stay broad while hydration is kept deliberately
      # small so new-product acquisition cannot starve customer search.
      CATALOG_ACQUISITION_CONCURRENCY = "2";
      CATALOG_ACQUISITION_CLAIM_BATCH_SIZE = "10";

      # CPU-only Ollama inference competes directly with search and discovery.
      CAPTION_WORKER_ENABLED = "false";
      MATERIAL_ENRICHMENT_WORKER_ENABLED = "false";

      # Retain a fresh customer-visibility snapshot every six hours. Shadow
      # walks remain limited to the fast, reliable Shopify catalogs validated
      # in production; heavyweight/partial TargetWalk retailers and Kith's
      # page-cap failure stay excluded until their walkers are repaired.
      AUDIT_WORKER_ENABLED = "true";
      AUDIT_WORKER_INTERVAL_SECONDS = "21600";
      CATALOG_WALK_SHADOW_ENABLED = "true";
      CATALOG_WALK_INTERVAL_SECONDS = "21600";
      CATALOG_WALK_DOMAINS = "aimeleondore.com,aloyoga.com,fearofgod.com,jjjjound.com,johnelliott.com,ksubi.com,mnml.la,octobersveryown.com,representclo.com,rh-ude.com,us.bape.com,wearebraindead.com";

      COOKIE_HARVESTER_SCRIPT_PATH = "${engineFlakePath}/scripts/harvest-cookies.js";

      # Evolutionary program generation token bounds
      MIN_GENERATION_TOKENS = "8";
      MAX_GENERATION_TOKENS = "30";
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

      # Use normal scheduling rather than real-time round-robin; CPU weights
      # give the engine preference without allowing it to starve PostgreSQL.
      Nice = 0;
      CPUSchedulingPolicy = "other";
      CPUWeight = 1000;

      # Balanced I/O priority: enough for ingestion without starving database
      # checkpoints and query reads.
      IOWeight = 500;

      # File descriptor limit: bump from default 1024 to hard limit.
      # The engine's socket backlog is 4096, and scraping/discovery/search
      # concurrently consume many FDs. Without this, cloudflared gets
      # "connection refused" when the FD pool is exhausted.
      LimitNOFILE = 524288;

      # ENV
      EnvironmentFile = envFile;
      WorkingDirectory = engineFlakePath;
      ExecStartPre = waitForQdrant;
      # Command-level values take precedence over the secret EnvironmentFile,
      # which still carries legacy audit and shadow-walk toggles.
      ExecStart = "${pkgs.coreutils}/bin/env AUDIT_WORKER_ENABLED=true CATALOG_WALK_SHADOW_ENABLED=true ${swagwatch-engine.packages.x86_64-linux.default}/bin/swagwatch_engine";
      Restart = "always";
      RestartSec = "5s";
    };
  };
}
