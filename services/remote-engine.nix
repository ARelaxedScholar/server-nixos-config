{ pkgs, swagwatch-engine, ... }:

let
  engineFlakePath = "/mnt/data/swagwatch-engine";
  vaultDir = "${engineFlakePath}/vault";
  envFile = "/persist/etc/secrets/remote-engine.env";
  waitForQdrant = pkgs.writeShellScript "wait-for-qdrant" ''
    qdrant_ready=false
    for attempt in $(${pkgs.coreutils}/bin/seq 1 180); do
      if ${pkgs.curl}/bin/curl --fail --silent --max-time 2 \
        http://127.0.0.1:6333/readyz > /dev/null; then
        qdrant_ready=true
        break
      fi
      ${pkgs.coreutils}/bin/sleep 2
    done

    if [ "$qdrant_ready" != true ]; then
      echo "Qdrant did not become ready within 6 minutes" >&2
      exit 1
    fi

    point_id="$(
      ${pkgs.curl}/bin/curl --fail --silent --max-time 10 \
        --header "content-type: application/json" \
        --data '{"limit":1,"with_payload":false,"with_vector":false}' \
        http://127.0.0.1:6333/collections/swagwatch_index/points/scroll \
        | ${pkgs.jq}/bin/jq --raw-output '.result.points[0].id // empty'
    )"

    if [ -z "$point_id" ]; then
      echo "Qdrant collection has no point available for index warmup" >&2
    else
      for vector_name in text image; do
        if ! ${pkgs.curl}/bin/curl --fail --silent --max-time 30 \
          --header "content-type: application/json" \
          --data "{\"query\":\"$point_id\",\"using\":\"$vector_name\",\"limit\":500,\"params\":{\"exact\":false,\"quantization\":{\"rescore\":false}},\"with_payload\":false}" \
          http://127.0.0.1:6333/collections/swagwatch_index/points/query \
          > /dev/null; then
          echo "Qdrant $vector_name index warmup failed; continuing with a cold index" >&2
        fi
      done
    fi
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
      # target overwhelmed the shared ZFS pool. Two domains with up to six
      # product jobs each preserves acquisition breadth at roughly 12-way
      # concurrency while leaving I/O capacity for customer search.
      DEFAULT_SCRAPER_CONCURRENCY = "4";
      SCRAPER_CONCURRENCY = "ssense.com:4,kith.com:4,aritzia.com:4,urban-planet.com:4,simons.ca:4,target.com:4";
      # Redis token-bucket limits: domain:burst_capacity:refill_per_second.
      # Suffix matching is supported, so asos.com also covers www.asos.com.
      SCRAPER_RATE_LIMITS = "asos.com:50:20,massimodutti.com:20:5,static.massimodutti.net:50:20,bershka.com:20:5,stradivarius.com:20:5,static.e-stradivarius.net:50:20,pullandbear.com:20:5,static.pullandbear.com:50:20,zara.com:20:5,oysho.com:20:5,static.oysho.net:50:20,kith.com:5:1.5";
      SCRAPE_DISCOVERY_CONCURRENCY = "4";
      SCRAPE_DOMAIN_CONCURRENCY = "2";
      SCRAPE_TARGETS_PER_DOMAIN_CONCURRENCY = "1";
      # Claim only enough work to keep the two active domains fed. A 2,000-row
      # lease did not add throughput and left large stale IN_PROGRESS batches
      # after a restart.
      SCRAPE_CLAIM_BATCH_SIZE = "50";
      SCRAPE_CLAIM_LEASE_HOURS = "2";

      # Ledger refreshes existing products; keep them responsive without
      # letting availability writes crowd out acquisition or customer reads.
      LEDGER_BATCH_SIZE = "10";
      LEDGER_DOMAIN_CONCURRENCY = "2";
      LEDGER_JOBS_PER_DOMAIN_CONCURRENCY = "2";

      # Catalog discovery may stay broad while hydration is kept deliberately
      # small so new-product acquisition cannot starve customer search.
      CATALOG_ACQUISITION_CONCURRENCY = "2";
      CATALOG_ACQUISITION_CLAIM_BATCH_SIZE = "10";

      # CPU-only Ollama inference competes directly with search and discovery.
      CAPTION_WORKER_ENABLED = "false";
      MATERIAL_ENRICHMENT_WORKER_ENABLED = "false";

      # Rebuild the fail-closed customer-visibility snapshot hourly so newly
      # acquired inventory does not remain hidden for most of a workday.
      # Shadow walks remain limited to reliable Shopify catalogs validated in
      # production. FashionNova is bounded to a durable 300-target slice;
      # Kith's page-cap failure stays excluded until its walker is repaired.
      AUDIT_WORKER_ENABLED = "true";
      AUDIT_WORKER_INTERVAL_SECONDS = "3600";
      CATALOG_WALK_SHADOW_ENABLED = "true";
      CATALOG_WALK_INTERVAL_SECONDS = "21600";
      CATALOG_WALK_DOMAINS = "aimeleondore.com,aloyoga.com,fashionnova.com,fearofgod.com,jjjjound.com,johnelliott.com,ksubi.com,mnml.la,octobersveryown.com,representclo.com,rh-ude.com,us.bape.com,wearebraindead.com";

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
      # Qdrant can take more than 90 seconds to map and load the 2.1M-vector
      # collection after a restart. Cover the six-minute readiness window plus
      # both optional 30-second index warmups.
      TimeoutStartSec = "8min";
      # Command-level values take precedence over the secret EnvironmentFile,
      # which still carries legacy audit and shadow-walk toggles.
      ExecStart = "${pkgs.coreutils}/bin/env AUDIT_WORKER_ENABLED=true CATALOG_WALK_SHADOW_ENABLED=true ${swagwatch-engine.packages.x86_64-linux.default}/bin/swagwatch_engine";
      Restart = "always";
      RestartSec = "5s";
    };
  };
}
