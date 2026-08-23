{
  config,
  pkgs,
  lib,
  swagwatch-engine,
  ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../../services/cloudflared.nix
    ../../services/remote-engine.nix
    ../../services/swagwatch-social-api.nix
    ../../services/animus.nix
    ../../services/headless-solver.nix
    ../../services/qdrant.nix
    ../../services/redis.nix
    ../../services/moondream.nix
    ../../services/hermes.nix
    ../../services/homelab-health.nix
    ../../services/watchtower.nix
    # ../../services/weaver.nix
    ../../services/uriel.nix
    ../../services/ciel.nix
    ../../services/forge.nix
  ];


  nixpkgs.overlays = [
    (final: prev: {
      pythonPackagesExtensions = (prev.pythonPackagesExtensions or []) ++ [
        (pyFinal: pyPrev: {
          sse-starlette = pyPrev.sse-starlette.overridePythonAttrs (old: {
            doCheck = false;
            propagatedBuildInputs = (old.propagatedBuildInputs or []) ++ [ pyPrev.starlette ];
          });
        })
      ];
    })
  ];

  networking.hostName = "swagwatch-engine";
  networking.hostId = "b4dc0ff3";
  networking.useDHCP = true;
  networking.nameservers = [
    "1.1.1.1"
    "8.8.8.8"
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.settings.max-jobs = 1;
  nix.settings.cores = 2;
  # Release compilation shares this host with the customer API. Nix build
  # workers inherit these limits, keeping deploys from competing at equal
  # priority with search, discovery, PostgreSQL, Redis, and Qdrant.
  systemd.services.nix-daemon.serviceConfig = {
    Nice = 15;
    CPUWeight = 10;
    IOWeight = 10;
  };
  nix.settings.trusted-users = [
    "root"
    "user"
  ];
  security.sudo.extraRules = [
    {
      users = [ "user" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
  nixpkgs.config.permittedInsecurePackages = [ "minio-2025-10-15T17-29-55Z" ];
  nix.settings.auto-optimise-store = true;
  nix.settings.substituters = [
    "https://cache.numtide.com"
    "https://cache.nixos.org"
  ];
  nix.settings.trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16Z+Qa2n8ixLSSQ8="
  ];
  programs.nh = {
    enable = true;
    clean = {
      enable = true;
      extraArgs = "--keep 3";
    };
  };

  fileSystems."/persist".neededForBoot = true;

  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };
  swapDevices = [
    { device = "/dev/zvol/zroot/swap"; }
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.zfs.forceImportRoot = true;
  boot.extraModprobeConfig = ''
    options zfs zfs_arc_max=5368709120
  '';

  boot.initrd.secrets = {
    "/data_drive.key" = "/persist/etc/secrets/data_drive.key";
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
    8082
    9000
    9001
    5432
  ];
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 11434 ];

  environment.binsh = "${pkgs.bash}/bin/sh";

  environment.etc."ssh/ssh_config.d/musa-openshell-sandbox.conf".text = ''
    Host musa-openshell-sandbox
      HostName musa-openshell-sandbox
      User sandbox
      ProxyCommand ${pkgs.bash}/bin/bash -c 'container="$(${pkgs.docker}/bin/docker ps --format "{{.Names}}" | ${pkgs.gnugrep}/bin/grep -m1 "^openshell-musa-sandbox-")"; test -n "$container"; exec ${pkgs.docker}/bin/docker exec -i "$container" /usr/sbin/sshd -i -e -o UsePAM=no -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -o PermitUserEnvironment=yes'
      IdentityFile /home/user/.hermes/profiles/musa/ssh/id_ed25519_openshell
      IdentitiesOnly yes
      StrictHostKeyChecking accept-new
      UserKnownHostsFile /home/user/.ssh/known_hosts
  '';

  boot.initrd.luks.devices."crypted_data" = {
    keyFile = lib.mkForce "/data_drive.key";
    keyFileSize = lib.mkForce 2048;
  };

  boot.initrd.systemd.services.rollback = {
    description = "Rollback ZFS root to blank snapshot";
    wantedBy = [ "initrd.target" ];
    after = [
      "zfs-import-zroot.service"
      "systemd-cryptsetup@crypted_os.service"
    ];
    before = [ "sysroot.mount" ];
    path = [ pkgs.zfs ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script = ''
      zfs list -t snapshot zroot/root@blank > /dev/null && zfs rollback -r zroot/root@blank || echo "Snapshot zroot/root@blank not found, skipping rollback."
    '';
  };

  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      port = 2222;
      authorizedKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID1qzN7jOZSdb2ppgP+ldtvxKt5ielBVcS6g+cbRa/lG angemmanuel.kouakou+professional@gmail.com"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO8VQdhvpNjpVmzSn4fgiRuesTMTtIJr63PTTBkzx6wv"
      ];
      hostKeys = [ "/persist/etc/secrets/initrd/ssh_host_ed25519_key" ];
    };
  };

  boot.initrd.systemd.enable = true;

  services.tailscale = {
enable = true;
extraSetFlags = [ "--ssh" ];
};

  services.forge = {
    enable = true;
    dataDir = "/var/lib/forge";
    vastaiEnvFile = "/persist/etc/secrets/vastai.env";
    reaper = {
      enable = true;
      dryRun = true;
      interval = "10min";
    };
  };

  services.journald.extraConfig = ''
    SystemMaxUse=500M
  '';

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;
    ensureDatabases = [
      "animus"
      "swagwatch"
    ];
    ensureUsers = [
      {
        name = "animus";
        ensureDBOwnership = true;
      }
      {
        name = "swagwatch";
        ensureDBOwnership = true;
      }
    ];
    settings = {
      io_method = "io_uring";
      shared_buffers = "2GB";
      # work_mem applies per sort/hash node and per connection. A 128 MiB
      # default can exhaust this 32 GiB host under concurrent API traffic.
      work_mem = "32MB";
      maintenance_work_mem = "1GB";
      max_connections = "100";
      autovacuum_naptime = "1min";
      autovacuum_vacuum_scale_factor = "0.05";
      autovacuum_analyze_scale_factor = "0.02";
      autovacuum_vacuum_cost_limit = "2000";
      random_page_cost = "1.1";
      effective_io_concurrency = "200";
      effective_cache_size = "20GB";
      checkpoint_timeout = "15min";
      checkpoint_completion_target = "0.9";
      max_wal_size = "4GB";
    };
  };

  systemd.services.postgresql = {
    requires = [ "var-lib-postgresql.mount" ];
    after = [ "var-lib-postgresql.mount" ];
    unitConfig = {
      ConditionPathIsMountPoint = "/var/lib/postgresql";
      # If crash recovery requires a restart, ensure the consumer API is
      # started once PostgreSQL is healthy instead of leaving it inactive.
      Upholds = "swagwatch-social-api.service";
    };
    # Production crash recovery can legitimately exceed systemd's two-minute
    # default while replaying WAL and completing the recovery checkpoint.
    serviceConfig.TimeoutStartSec = "15min";
  };

  systemd.services."notify-failure@" = {
    description = "Failure alert for %i";
    serviceConfig.Type = "oneshot";
    scriptArgs = "%i";
    script = ''
      UNIT="$1"
      MSG="[$(uname -n)] $(date -Is) systemd unit FAILED: $UNIT"
      echo "$MSG" | ${pkgs.systemd}/bin/systemd-cat -t failure-alert -p emerg
      echo "$MSG" >> /persist/var/lib/failure-alerts.log
      ${pkgs.util-linux}/bin/wall "$MSG" 2>/dev/null || true
      if [ -r /persist/etc/secrets/alert-webhook-url ]; then
        ${pkgs.curl}/bin/curl -fsS -m 10 -d "$MSG" "$(cat /persist/etc/secrets/alert-webhook-url)" || true
      fi
    '';
  };

  environment.interactiveShellInit = ''
    if [ -s /persist/var/lib/failure-alerts.log ]; then
      printf '\033[1;31m=== UNRESOLVED FAILURE ALERTS (clear: sudo truncate -s0 /persist/var/lib/failure-alerts.log) ===\033[0m\n'
      tail -n 5 /persist/var/lib/failure-alerts.log
    fi
  '';

  systemd.services.zpool-capacity-check = {
    description = "Alert when a zpool crosses 80% capacity";
    serviceConfig.Type = "oneshot";
    unitConfig.OnFailure = [ "notify-failure@%p.service" ];
    script = ''
      FULL=0
      while read -r POOL CAP; do
        CAP=''${CAP%"%"}
        if [ "$CAP" -ge 80 ]; then
          echo "zpool $POOL is at $CAP% capacity" | ${pkgs.systemd}/bin/systemd-cat -t failure-alert -p warning
          echo "[$(uname -n)] $(date -Is) zpool $POOL at $CAP% capacity" >> /persist/var/lib/failure-alerts.log
          FULL=1
        fi
      done < <(${pkgs.zfs}/bin/zpool list -H -o name,capacity)
      exit $FULL
    '';
  };

  systemd.timers.zpool-capacity-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
      Unit = "zpool-capacity-check.service";
    };
  };

  systemd.services.zfs-backup-persist = {
    description = "Backup persist dataset to datapool storage";
    unitConfig.OnFailure = [ "notify-failure@%p.service" ];
    serviceConfig = {
      Type = "oneshot";
      # A full reseed can move more than 150 GiB. Keep it strictly
      # best-effort so backup repair cannot make the customer API unusable.
      Nice = 15;
      CPUWeight = 10;
      IOWeight = 10;
      IOSchedulingClass = "idle";
      ExecStart = pkgs.writeShellScript "zfs-backup" ''
        set -euo pipefail
        SOURCE_DATASET="zroot/persist"
        DEST_DATASET="datapool/backups/persist_mirror"
        RESEED_DATASET="datapool/backups/persist_mirror_reseed"
        PREVIOUS_DATASET="datapool/backups/persist_mirror_previous"

        ${pkgs.zfs}/bin/zfs list datapool/backups >/dev/null 2>&1 || ${pkgs.zfs}/bin/zfs create datapool/backups

        # Recover an interrupted dataset swap before attempting another backup.
        if ! ${pkgs.zfs}/bin/zfs list "$DEST_DATASET" >/dev/null 2>&1 \
          && ${pkgs.zfs}/bin/zfs list "$PREVIOUS_DATASET" >/dev/null 2>&1; then
          ${pkgs.zfs}/bin/zfs rename "$PREVIOUS_DATASET" "$DEST_DATASET"
        fi
        if ${pkgs.zfs}/bin/zfs list "$DEST_DATASET" >/dev/null 2>&1 \
          && ${pkgs.zfs}/bin/zfs list "$PREVIOUS_DATASET" >/dev/null 2>&1; then
          ${pkgs.zfs}/bin/zfs destroy -r "$PREVIOUS_DATASET"
        fi
        if ${pkgs.zfs}/bin/zfs list "$RESEED_DATASET" >/dev/null 2>&1; then
          ${pkgs.zfs}/bin/zfs destroy -r "$RESEED_DATASET"
        fi

        if ${pkgs.zfs}/bin/zfs list "$DEST_DATASET" >/dev/null 2>&1; then
          RESUME_TOKEN=$(${pkgs.zfs}/bin/zfs get -H -o value receive_resume_token "$DEST_DATASET")
          if [ "$RESUME_TOKEN" != "-" ]; then
            ${pkgs.zfs}/bin/zfs receive -A "$DEST_DATASET"
          fi
        fi

        TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
        SNAP_NAME="$SOURCE_DATASET@backup_$TIMESTAMP"
        ${pkgs.zfs}/bin/zfs snapshot "$SNAP_NAME"
        COMMON=""
        if ${pkgs.zfs}/bin/zfs list "$DEST_DATASET" >/dev/null 2>&1; then
          for dest_snap in $(${pkgs.zfs}/bin/zfs list -H -t snapshot -o name -S creation -d1 "$DEST_DATASET" | cut -d@ -f2); do
            if ${pkgs.zfs}/bin/zfs list "$SOURCE_DATASET@$dest_snap" >/dev/null 2>&1; then
              COMMON="$dest_snap"
              break
            fi
          done
        fi

        echo "Starting ZFS replication for $SNAP_NAME (incremental from: ''${COMMON:-none, full send})..."
        if [ -n "$COMMON" ]; then
          ${pkgs.zfs}/bin/zfs send -v -I "@$COMMON" "$SNAP_NAME" | ${pkgs.zfs}/bin/zfs receive -Fuv \
            -o mountpoint=none -o canmount=off \
            "$DEST_DATASET"
        else
          ${pkgs.zfs}/bin/zfs send -v "$SNAP_NAME" | ${pkgs.zfs}/bin/zfs receive -uv \
            -o mountpoint=none -o canmount=off \
            "$RESEED_DATASET"
          ${pkgs.zfs}/bin/zfs list "$RESEED_DATASET@''${SNAP_NAME#*@}" >/dev/null

          if ${pkgs.zfs}/bin/zfs list "$DEST_DATASET" >/dev/null 2>&1; then
            ${pkgs.zfs}/bin/zfs rename "$DEST_DATASET" "$PREVIOUS_DATASET"
          fi
          if ! ${pkgs.zfs}/bin/zfs rename "$RESEED_DATASET" "$DEST_DATASET"; then
            if ${pkgs.zfs}/bin/zfs list "$PREVIOUS_DATASET" >/dev/null 2>&1; then
              ${pkgs.zfs}/bin/zfs rename "$PREVIOUS_DATASET" "$DEST_DATASET"
            fi
            exit 1
          fi
          if ${pkgs.zfs}/bin/zfs list "$PREVIOUS_DATASET" >/dev/null 2>&1; then
            ${pkgs.zfs}/bin/zfs destroy -r "$PREVIOUS_DATASET"
          fi
        fi

        while read -r old_snapshot; do
          if [ -n "$old_snapshot" ]; then
            ${pkgs.zfs}/bin/zfs destroy -r "$old_snapshot"
          fi
        done < <(${pkgs.zfs}/bin/zfs list -H -t snapshot -o name -S creation -d1 "$DEST_DATASET" \
          | tail -n +31)

        # The destination keeps the restore history. The source only needs the
        # newest common snapshot as the next incremental-send baseline; keeping
        # another generation pins a full day of database churn on the small
        # root pool and can exhaust it before the following backup.
        while read -r old_snapshot; do
          if [ -n "$old_snapshot" ]; then
            ${pkgs.zfs}/bin/zfs destroy "$old_snapshot"
          fi
        done < <(${pkgs.zfs}/bin/zfs list -H -t snapshot -o name -S creation -d1 "$SOURCE_DATASET" \
          | tail -n +2)

        echo "Backup complete: $SNAP_NAME replicated to $DEST_DATASET."
      '';
    };
  };

  systemd.timers.zfs-backup-persist = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "03:00";
      Persistent = true;
      Unit = "zfs-backup-persist.service";
    };
  };

  services.minio = {
    enable = true;
    dataDir = [ "/var/lib/minio/data" ];
    rootCredentialsFile = "/persist/etc/secrets/animus-minio-credentials";
  };

  systemd.tmpfiles.rules = [
    "d /persist/var/lib/minio        0750 minio minio -"
    "d /var/lib/hermes/workspace 0755 hermes hermes -"
    "d /var/lib/hermes/workspace/server-nixos-config 0755 hermes hermes -"
    "d /var/lib/hermes/workspace 0755 hermes hermes -"
    "d /var/lib/hermes/workspace/server-nixos-config 0755 hermes hermes -"
    "d /persist/var/lib/minio/data   0750 minio minio -"
    "d /persist/var/lib/minio/config 0750 minio minio -"
    "d /persist/var/lib/minio/certs  0750 minio minio -"
    "d /var/lib/hermes/reports 0750 hermes hermes - -"
    "d /var/lib/homelab-health 0750 root hermes - -"
    "d /var/lib/honcho        0755 user users - -"
    "d /var/lib/honcho/source 0755 user users - -"
  ];

  systemd.services.minio = {
    requires = [ "var-lib-minio.mount" ];
    after = [ "var-lib-minio.mount" ];
  };

  services.animus = {
    enable = true;
    envFile = /persist/etc/secrets/animus.env;
  };

  services.hermes = {
    enable = true;  # disabled in favor of per-profile gateway units below
    manageUser = false;
    user = "user";
    group = "users";
    stateDir = "/home/user";
    envFile = "/persist/etc/secrets/hermes.env";
  };

  # --- Hermes Agent gateways ---
systemd.services.hermes-gateway = {
  description = "Hermes Agent gateway — Ariel (default) profile";
  wantedBy = [ "multi-user.target" ];
  after = [
    "network-online.target"
    "hermes-init-config.service"
  ];
  wants = [ "network-online.target" ];
  requires = [ "hermes-init-config.service" ];

  environment = {
    HOME = "/home/user";
    HERMES_HOME = "/home/user/.hermes";
  };

  serviceConfig = {
    Type = "simple";
    User = "user";
    Group = "users";
    WorkingDirectory = "/home/user";
    EnvironmentFile = [ "-/persist/etc/secrets/hermes.env" ];
    ExecStart = "/run/current-system/sw/bin/hermes gateway run --replace";
    Restart = "on-failure";
    RestartSec = "15s";
    StartLimitIntervalSec = 300;
    StartLimitBurst = 5;
  };
};

  systemd.services.hermes-midas-gateway = {
    description = "Hermes Agent gateway — Midas profile";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "openshell-gateway.service"
      "openshell-sandbox-setup.service"
    ];
    wants = [
      "network-online.target"
      "openshell-gateway.service"
    ];
    environment = {
      HOME = "/home/user";
      HERMES_HOME = "/home/user/.hermes";
      HERMES_PROFILE = "midas";
    };
    path = [
      pkgs.openssh
      pkgs.docker
    ];
    serviceConfig = {
      Type = "simple";
      User = "user";
      Group = "users";
      WorkingDirectory = "/home/user";
      EnvironmentFile = [ "-/persist/etc/secrets/midas.env" ];
      ExecStart = "/run/current-system/sw/bin/hermes -p midas gateway run --replace";
      Restart = "on-failure";
      RestartSec = "15s";
      TimeoutStopSec = "240s";
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
    };
  };

  systemd.services.hermes-musa-gateway = {
    description = "Hermes Agent gateway — Musa profile";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "openshell-gateway.service"
      "openshell-sandbox-setup.service"
    ];
    wants = [
      "network-online.target"
      "openshell-gateway.service"
    ];
    environment = {
      HOME = "/home/user";
      HERMES_HOME = "/home/user/.hermes";
      HERMES_PROFILE = "musa";
      TERMINAL_ENV = "ssh";
      TERMINAL_CWD = "/sandbox";
      TERMINAL_SSH_HOST = "musa-openshell-sandbox";
      TERMINAL_SSH_USER = "sandbox";
      TERMINAL_SSH_PORT = "22";
      TERMINAL_SSH_KEY = "/home/user/.hermes/profiles/musa/ssh/id_ed25519_openshell";
    };
    path = [
      pkgs.openssh
      pkgs.docker
    ];
    serviceConfig = {
      Type = "simple";
      User = "user";
      Group = "users";
      WorkingDirectory = "/home/user";
      EnvironmentFile = [ "-/persist/etc/secrets/musa.env" ];
      ExecStart = "/run/current-system/sw/bin/hermes -p musa gateway run --replace";
      Restart = "on-failure";
      RestartSec = "15s";
      TimeoutStopSec = "240s";
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
    };
  };

  # --- Honcho Memory Server ---

  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      data-root = "/mnt/data/docker";
    };
  };

  # Honcho DB + Redis via oci-containers (declarative)
  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      honcho-db = {
        image = "pgvector/pgvector:pg15";
        ports = [ "127.0.0.1:5433:5432" ];
        volumes = [ "honcho-pgdata:/var/lib/postgresql/data" ];
        environment = {
          POSTGRES_DB = "honcho";
          POSTGRES_USER = "postgres";
          POSTGRES_PASSWORD = "changeme";
          PGDATA = "/var/lib/postgresql/data/pgdata";
        };
        extraOptions = [
          "--network=honcho-net"
          "--health-cmd=pg_isready -U postgres -d honcho"
          "--health-interval=5s"
          "--health-timeout=5s"
          "--health-retries=10"
        ];
        autoStart = true;
      };
      honcho-redis = {
        image = "redis:8.2-alpine";
        ports = [ "127.0.0.1:6380:6379" ];
        volumes = [ "honcho-redis-data:/data" ];
        extraOptions = [
          "--network=honcho-net"
        ];
        autoStart = true;
      };
    };
  };

  # Create Docker network for Honcho containers (needed for DNS resolution by container name)
  systemd.services.honcho-docker-network = {
    description = "Create Docker network for Honcho stack";
    wantedBy = [ "multi-user.target" ];
    before = [ "docker-honcho-db.service" "docker-honcho-redis.service" "docker-honcho-api.service" ];
    requires = [ "docker.service" ];
    after = [ "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.docker}/bin/docker network inspect honcho-net >/dev/null 2>&1 || ${pkgs.docker}/bin/docker network create --driver bridge honcho-net'";
    };
  };

  # Note: honcho-api image is built manually via docker build
  # This oneshot build service has networking issues on this host.
  # Image build is handled imperatively until NixOS config is updated.
  systemd.services.honcho-build = {
    description = "Build Honcho API Docker image (disabled - see notes)";
    wantedBy = [ ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/run/current-system/true";
      RemainAfterExit = true;
    };
  };

  # Honcho API container
  virtualisation.oci-containers.containers.honcho-api = {
    image = "honcho-api:latest";
    dependsOn = [ "honcho-db" "honcho-redis" ];
    ports = [ "127.0.0.1:8002:8000" ];
    environment = {
      DB_CONNECTION_URI = "postgresql+psycopg://postgres:changeme@honcho-db:5432/honcho";
      CACHE_URL = "redis://honcho-redis:6379/0?suppress=true";
      CACHE_ENABLED = "true";
      AUTH_ENABLED = "false";
      LOG_LEVEL = "INFO";
      VECTOR_STORE_TYPE = "pgvector";
      EMBED_MESSAGES = "false";
      DERIVER_ENABLED = "false";
      PEER_CARD_ENABLED = "true";
      SUMMARY_ENABLED = "false";
      DREAM_ENABLED = "false";
    };
    extraOptions = [
      "--network=honcho-net"
    ];
    autoStart = true;
  };

  # --- Other services ---

  services.watchtower = {
    enable = true;
    envFile = /persist/etc/secrets/watchtower.env;
  };

#  services.weaver = {
#    enable = false;
#    envFile = /persist/etc/secrets/weaver.env;
#    enableIntelligence = true;
#    enableLeadgen = true;
#  };

  # Uriel retired 2026-08-23. Ciel (pi SDK daemon) is the 24/7 agent; its
  # memory was migrated from /var/lib/uriel/workspace/memory.db. The uriel
  # persistence entry below is retained as a pre-migration backup.
  services.uriel = {
    enable = false;
    envFile = /persist/etc/secrets/uriel.env;
    soulFile = /persist/etc/secrets/soul.md;
    sharedKnowledgeVault = "/home/user/.hermes/profiles/midas/shared-memory-vault";
    # The production host is CPU-only, so use the configured NVIDIA NIM
    # credentials for both fast cognition and semantic memory.
    sys1Stub = false;
    extraEnv = {
      SYS1_BACKEND = "nvidia";
      EMBEDDING_PROVIDER = "nvidia";
      NVIDIA_EMBED_MODEL = "nvidia/nv-embedqa-e5-v5";
      SEARXNG_URL = "http://127.0.0.1:8888";
      NIM_MAX_TOKENS = "4096";
      NIM_MODEL_LIGHT = "nvidia/nvidia-nemotron-nano-9b-v2";
      NIM_REQUEST_TIMEOUT_SECS = "90";
    };
  };

  # Private, no-key metasearch broker for Uriel. It is deliberately bound to
  # loopback and is not exposed through the firewall; Uriel's OpenShell
  # execution sandbox remains network-denied.
  services.searx = {
    enable = true;
    openFirewall = false;
    settings = {
      server = {
        bind_address = "127.0.0.1";
        port = 8888;
        secret_key = "uriel-loopback-search-no-browser-sessions";
      };
      search = {
        safe_search = 1;
        autocomplete = "";
        formats = [
          "html"
          "json"
        ];
      };
    };
  };

  systemd.services.uriel = {
    after = [ "searx.service" ];
    wants = [ "searx.service" ];
  };

  # Ciel = Uriel evolved, on the pi SDK. Keep Uriel running until Ciel has
  # proven itself (Discord token stays out of ciel.env until then), then set
  # services.uriel.enable = false and remove its persistence entry below.
  services.ciel = {
    enable = true;
    envFile = "/persist/etc/secrets/ciel.env";
    soulFile = "/persist/etc/secrets/soul.md";
    agentDir = "/persist/etc/secrets/ciel-agent";
  };

  services.openshell = {
    enable = true;
  };

  services.homelabHealth = {
    enable = true;
    reportPath = "/var/lib/homelab-health/latest.txt";

    healthUrls = [
      "http://127.0.0.1:81"
      "http://127.0.0.1:8000"
      "http://127.0.0.1:8081"
      "http://127.0.0.1:8082"
      "http://127.0.0.1:3000"
      "http://127.0.0.1:4533"
      "http://127.0.0.1:5000"
      "http://127.0.0.1:5984"
      "http://127.0.0.1:9000"
      "http://127.0.0.1:2283"
    ];

    pathChecks = [
      "/var/lib/hermes"
      "/var/lib/homelab-health"
    ];

    logTargets = [ ];
  };

  services.moondream = {
    # Keep the model definition available for a future GPU or separate host,
    # but do not run CPU-only inference on the production search machine.
    enable = false;
    modelDir = "/persist/cache/ollama";
  };

  users.users.root.hashedPasswordFile = "/persist/etc/secrets/root-password";
  users.users.user = {
    isNormalUser = true;
    hashedPasswordFile = "/persist/etc/secrets/user-password";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID1qzN7jOZSdb2ppgP+ldtvxKt5ielBVcS6g+cbRa/lG angemmanuel.kouakou+professional@gmail.com"
    ];
    extraGroups = [
      "forge"
      "docker"
      "wheel"
    ];
  };

  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/log"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/var/lib/tailscale"
      "/var/lib/postgresql"
      "/var/lib/minio"
      {
        directory = "/var/lib/qdrant";
        user = "qdrant";
        group = "qdrant";
        mode = "0700";
      }
      {
        directory = "/var/lib/redis";
        user = "redis";
        group = "redis";
        mode = "0700";
      }
      "/var/lib/animus"
#      {
#        directory = "/var/lib/watchtower";
#        user = "watchtower";
#        group = "watchtower";
#        mode = "0750";
#      }
#      {
#        directory = "/var/lib/weaver";
#        user = "weaver";
#        group = "weaver";
#        mode = "0750";
#      }
      {
        directory = "/var/lib/uriel";
        user = "uriel";
        group = "uriel";
        mode = "0755";
      }
      {
        directory = "/var/lib/ciel";
        user = "ciel";
        group = "ciel";
        mode = "0755";
      }
      "/home/user/"
      "/persist/cache"
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
  };

  environment.systemPackages = with pkgs; [
    postgresql_18
    pgcli
    chromium
    nh
    llama-cpp
    python3
    dig
  ];

  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    glibc
    libX11
    libXcomposite
    libXdamage
    libXext
    libXfixes
    libXrandr
    libXrender
    libGL
    nss
    nspr
    fontconfig
    freetype
    dbus
    glib
    atk
    at-spi2-atk
    cups
    expat
    libdrm
    mesa
    libxshmfence
    libuuid
  ];
}
