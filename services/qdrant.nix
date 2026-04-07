{ lib, ... }:

{
  services.qdrant = {
    enable = true;
    settings = {
      storage = {
        # Keep the HNSW navigation graph in DDR3 RAM for fast vector search
        hnsw_index.on_disk = false;
        performance = {
          # Throttle global optimisation CPU budget to 1 core so scraper/animus
          # have headroom.  In Qdrant ≥ 1.13 the correct key is
          # `optimizer_cpu_budget` (positive = exact count); the old
          # `max_optimization_threads` key was removed from PerformanceConfig
          # and its presence as an integer caused config-rs 0.15.x to fail
          # deserialization.
          optimizer_cpu_budget = 1;
          # Suppress the stale NixOS-module default (max_optimization_threads: 1)
          # so it does not appear as a concrete integer in the generated YAML.
          max_optimization_threads = lib.mkForce null;
        };
      };
    };
  };

  # Qdrant's NixOS module uses DynamicUser + StateDirectory, which conflicts
  # with the impermanence bind mount on /var/lib/qdrant (systemd exit 238).
  # Use a static user instead and let impermanence manage the directory.
  users.users.qdrant = {
    isSystemUser = true;
    group = "qdrant";
  };
  users.groups.qdrant = { };

  # Ensure the persistent source directory exists with the correct ownership
  # before the bind mount is established.
  systemd.tmpfiles.rules = [
    "d /persist/var/lib/qdrant 0700 qdrant qdrant -"
  ];

  systemd.services.qdrant = {
    # Wait for the impermanence bind mount before starting
    requires = [ "var-lib-qdrant.mount" ];
    after = [ "var-lib-qdrant.mount" ];
    unitConfig = {
      # If the bind mount failed for any reason, skip the service rather than
      # starting qdrant against the empty volatile directory.
      ConditionPathIsMountPoint = "/var/lib/qdrant";
    };
    serviceConfig = {
      # Disable DynamicUser so systemd doesn't try to manipulate the bind-mounted
      # StateDirectory (which causes exit code 238 / EXIT_STATE_DIRECTORY).
      DynamicUser = lib.mkForce false;
      User = "qdrant";
      Group = "qdrant";
      # Impermanence already provides /var/lib/qdrant; don't let systemd
      # manage (and conflict with) the directory.
      StateDirectory = lib.mkForce "";
      # Memory guardrails: allow up to 5GB before throttling, hard cap at 6GB
      MemoryHigh = "5G";
      MemoryMax = "6G";
    };
  };
}
