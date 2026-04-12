{ lib, ... }:

{
  services.qdrant = {
    enable = true;
    settings = {
      service = {
        host = "0.0.0.0";
      };
      storage = {
        # Keep the HNSW navigation graph in DDR3 RAM for fast vector search
        hnsw_index.on_disk = false;
        # Throttle optimization to 1 thread so scraper/animus have CPU headroom
        performance.max_optimization_threads = 1;
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
