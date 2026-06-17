{
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../../services/cloudflared.nix
    ../../services/remote-engine.nix
    ../../services/animus.nix
    ../../services/headless-solver.nix
    ../../services/qdrant.nix
    ../../services/redis.nix
    ../../services/moondream.nix
    ../../services/hermes.nix
    ../../services/homelab-health.nix
    ../../services/watchtower.nix
    ../../services/weaver.nix
    ../../services/uriel.nix
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
  nix.settings.trusted-users = [
    "root"
    "user"
  ];
  nix.settings.auto-optimise-store = true;
  nix.settings.substituters = [
    "https://cache.numtide.com"
    "https://cache.nixos.org"
  ];
  nix.settings.trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16Z+Qa2n8ixLSSQ8="
  ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  programs.nh = {
    enable = true;
    clean = {
      enable = true;
      extraArgs = "--keep 5 --keep-since 14d";
    };
  };

  fileSystems."/persist".neededForBoot = true;

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
    9000
    9001
    5432
  ];
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 11434 ];

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
      ];
      hostKeys = [ "/persist/etc/secrets/initrd/ssh_host_ed25519_key" ];
    };
  };

  boot.initrd.systemd.enable = true;

  services.tailscale.enable = true;

  services.journald.extraConfig = ''
    SystemMaxUse=500M
  '';

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;
    ensureDatabases = [
      "animus"
      "swagwatch"
      "watchtower"
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
      {
        name = "watchtower";
        ensureDBOwnership = true;
      }
    ];
    settings = {
      io_method = "io_uring";
      shared_buffers = "4GB";
      work_mem = "128MB";
      max_connections = "100";
      autovacuum_naptime = "1min";
      autovacuum_vacuum_scale_factor = "0.05";
      autovacuum_analyze_scale_factor = "0.02";
      random_page_cost = "1.1";
      effective_io_concurrency = "200";
      effective_cache_size = "20GB";
    };
  };

  systemd.services.postgresql = {
    requires = [ "var-lib-postgresql.mount" ];
    after = [ "var-lib-postgresql.mount" ];
    unitConfig.ConditionPathIsMountPoint = "/var/lib/postgresql";
  };

  # Generic failure alarm: attach with unitConfig.OnFailure = [ "notify-failure@%p.service" ];
  # Alerts persist in /persist/var/lib/failure-alerts.log and are shown on every
  # interactive login until the file is truncated. For phone push, write a ntfy
  # topic URL (e.g. https://ntfy.sh/<random-secret-topic>) to
  # /persist/etc/secrets/alert-webhook-url and subscribe to it in the ntfy app.
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

  # Early warning before a full pool starts breaking services
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
      ExecStart = pkgs.writeShellScript "zfs-backup" ''
        set -euo pipefail
        ${pkgs.zfs}/bin/zfs list datapool/backups >/dev/null 2>&1 || ${pkgs.zfs}/bin/zfs create datapool/backups

        # Clear any resume token from a previous interrupted receive
        ${pkgs.zfs}/bin/zfs receive -A datapool/backups/persist_mirror 2>/dev/null || true

        # Prune destination snapshots BEFORE sending — ensures room for the incoming stream
        ${pkgs.zfs}/bin/zfs list -H -t snapshot -o name -S creation \
          | grep "datapool/backups/persist_mirror@backup_" \
          | tail -n +31 \
          | xargs -n 1 ${pkgs.zfs}/bin/zfs destroy -r 2>/dev/null || true

        TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
        SNAP_NAME="zroot/persist@backup_$TIMESTAMP"
        ${pkgs.zfs}/bin/zfs snapshot "$SNAP_NAME"

        # Incremental send from the newest snapshot present on both sides.
        # No -R: a replicated stream received with -F would destroy destination
        # snapshots that were pruned on the source, defeating the 30-day
        # retention on datapool while we keep only 2 on zroot.
        COMMON=""
        for dest_snap in $(${pkgs.zfs}/bin/zfs list -H -t snapshot -o name -S creation -d1 datapool/backups/persist_mirror 2>/dev/null | cut -d@ -f2); do
          if ${pkgs.zfs}/bin/zfs list "zroot/persist@$dest_snap" >/dev/null 2>&1; then
            COMMON="$dest_snap"
            break
          fi
        done

        echo "Starting ZFS replication for $SNAP_NAME (incremental from: ''${COMMON:-none, full send})..."
        if [ -n "$COMMON" ]; then
          ${pkgs.zfs}/bin/zfs send -v -I "@$COMMON" "$SNAP_NAME" | ${pkgs.zfs}/bin/zfs receive -Fuv \
            -o mountpoint=none -o canmount=off \
            datapool/backups/persist_mirror
        else
          ${pkgs.zfs}/bin/zfs send -v "$SNAP_NAME" | ${pkgs.zfs}/bin/zfs receive -Fuv \
            -o mountpoint=none -o canmount=off \
            datapool/backups/persist_mirror
        fi

        # Keep only the 2 newest snapshots on the cramped source pool;
        # the 30-day history lives on datapool/backups/persist_mirror.
        ${pkgs.zfs}/bin/zfs list -H -t snapshot -o name -S creation \
          | grep "zroot/persist@backup_" \
          | tail -n +3 \
          | xargs -n 1 ${pkgs.zfs}/bin/zfs destroy 2>/dev/null || true

        echo "Backup complete. 76k garments secured."
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
    enable = true;
    envFile = "/persist/etc/secrets/hermes.env";
    # model = "anthropic/claude-sonnet-4";  # override if you prefer another model
  };

  services.watchtower = {
    enable = true;
    envFile = /persist/etc/secrets/watchtower.env;
  };

  services.weaver = {
    enable = true;
    envFile = /persist/etc/secrets/weaver.env;
    enableIntelligence = true;
    enableLeadgen = true;
  };

  services.uriel = {
    enable = true;
    envFile = /persist/etc/secrets/uriel.env;
    soulFile = /persist/etc/secrets/uriel-soul.md;
    sys1Stub = false;  # Real Sys1 via Ollama (urielsys1)
  };

  services.homelabHealth = {
    enable = true;
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
  };

  services.moondream = {
    enable = true;
    # Model and host/port defaults match what swagwatch-engine expects
    # (model = "moondream", host = "127.0.0.1", port = 11434)
    # Persist downloaded models across reboots
    modelDir = "/persist/cache/ollama";
  };

  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      data-root = "/mnt/data/docker";
    };
  };

  users.users.root.hashedPasswordFile = "/persist/etc/secrets/root-password";
  users.users.user = {
    isNormalUser = true;
    hashedPasswordFile = "/persist/etc/secrets/user-password";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID1qzN7jOZSdb2ppgP+ldtvxKt5ielBVcS6g+cbRa/lG angemmanuel.kouakou+professional@gmail.com"
    ];
    extraGroups = [
      "docker"
      "hermes"
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
      {
        directory = "/var/lib/watchtower";
        user = "watchtower";
        group = "watchtower";
        mode = "0750";
      }
      {
        directory = "/var/lib/weaver";
        user = "weaver";
        group = "weaver";
        mode = "0750";
      }
      {
        directory = "/var/lib/uriel";
        user = "uriel";
        group = "uriel";
        mode = "0755";
      }
      "/home/user/"
      # hermes-agent state dirs are managed internally by the NixOS module
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
