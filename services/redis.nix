{ lib, ... }:

{
  services.redis.servers."" = {
    enable = true;
    bind = "127.0.0.1";
    port = 6379;
    settings = {
      # RDB snapshots: persist after N seconds if at least M keys changed
      save = [ "900 1" "300 10" "60 10000" ];
      # AOF for durability: every write is fsync'd at most once per second
      appendonly = "yes";
      appendfsync = "everysec";
    };
  };

  # Static user to avoid DynamicUser conflicts with the impermanence bind mount
  # (same fix as qdrant.nix – DynamicUser + StateDirectory + bind mount = exit 238)
  users.users.redis = {
    isSystemUser = true;
    group = "redis";
  };
  users.groups.redis = { };

  # Ensure the persistent source directory exists with the correct ownership
  # before impermanence establishes the bind mount.
  systemd.tmpfiles.rules = [
    "d /persist/var/lib/redis            0700 redis redis -"
    "d /persist/var/lib/redis/appendonlydir 0700 redis redis -"
  ];

  systemd.services.redis = {
    # Wait for the impermanence bind mount before starting
    requires = [ "var-lib-redis.mount" ];
    after = [ "var-lib-redis.mount" ];
    unitConfig = {
      # Skip the service if the bind mount failed rather than starting Redis
      # against an empty volatile directory and losing all data.
      ConditionPathIsMountPoint = "/var/lib/redis";
    };
    serviceConfig = {
      # Disable DynamicUser so systemd doesn't fight the bind-mounted directory
      DynamicUser = lib.mkForce false;
      User = "redis";
      Group = "redis";
      # Impermanence already provides /var/lib/redis; don't let systemd
      # manage (and potentially conflict with) the StateDirectory.
      StateDirectory = lib.mkForce "";
    };
  };
}
