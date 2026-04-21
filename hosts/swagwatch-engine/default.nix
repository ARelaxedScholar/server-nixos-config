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
  ];

  networking.hostName = "swagwatch-engine";
  networking.hostId = "b4dc0ff3";
  networking.useDHCP = true;
  networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.settings.trusted-users = [ "root" "user" ];

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

  systemd.services.zfs-backup-persist = {
    description = "Backup persist dataset to datapool storage";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "zfs-backup" ''
        set -e
        ${pkgs.zfs}/bin/zfs list datapool/backups >/dev/null 2>&1 || ${pkgs.zfs}/bin/zfs create datapool/backups

        TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
        SNAP_NAME="zroot/persist@backup_$TIMESTAMP"
        ${pkgs.zfs}/bin/zfs snapshot "$SNAP_NAME"

        echo "Starting ZFS replication for $SNAP_NAME..."
        ${pkgs.zfs}/bin/zfs send -vR "$SNAP_NAME" | ${pkgs.zfs}/bin/zfs receive -Fuv datapool/backups/persist_mirror

        ${pkgs.zfs}/bin/zfs list -H -t snapshot -o name -S creation | grep "zroot/persist@backup_" | tail -n +32 | xargs -n 1 ${pkgs.zfs}/bin/zfs destroy || true
        ${pkgs.zfs}/bin/zfs list -H -t snapshot -o name -S creation | grep "datapool/backups/persist_mirror@backup_" | tail -n +32 | xargs -n 1 ${pkgs.zfs}/bin/zfs destroy || true

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
      { directory = "/var/lib/qdrant"; user = "qdrant"; group = "qdrant"; mode = "0700"; }
      { directory = "/var/lib/redis"; user = "redis"; group = "redis"; mode = "0700"; }
      "/var/lib/animus"
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
