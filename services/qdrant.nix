{ ... }:

{
  services.qdrant = {
    enable = true;
    settings = {
      storage = {
        # Keep the HNSW navigation graph in DDR3 RAM for fast vector search
        hnsw_index.on_disk = false;
        # Throttle optimization to 1 thread so scraper/animus have CPU headroom
        performance.max_optimization_threads = 1;
      };
    };
  };

  # Memory guardrails: allow up to 5GB before throttling, hard cap at 6GB
  systemd.services.qdrant.serviceConfig = {
    MemoryHigh = "5G";
    MemoryMax = "6G";
  };
}
