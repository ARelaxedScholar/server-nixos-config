{
  config,
  pkgs,
  lib,
  ...
}:

{
  networking.useDHCP = true;
networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];

  # Imports hardware specifics and the Disko storage layout
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ./services/cloudflared.nix
    ./services/remote-engine.nix  
    ./services/animus.nix
  ];

# PostgreSQL Configuration
services.postgresql = {
  enable = true;
  package = pkgs.postgresql_17; 

  # Create both databases
  ensureDatabases = [ 
    "animus" 
    "swagwatch" 
  ];

  # Create dedicated users for each service
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

  # Optimization for high-frequency scraping on your Optiplex
  settings = {
    # This ensures 61.8k garments + recent ledger stay in RAM.
    shared_buffers = "12GB"; 

    # Keep these for stability
    work_mem = "256MB";      
    max_connections = "100";
    
    # Aggressive cleanup stays 
    autovacuum_naptime = "1min";
    autovacuum_vacuum_scale_factor = "0.05";
    autovacuum_analyze_scale_factor = "0.02";

    # SSD Optimization
    random_page_cost = "1.1"; 
    effective_io_concurrency = "200";
    effective_cache_size = "24GB"; # Tells the DB it can use the rest of RAM for OS cache
  };
};

# MinIO and Networking stay the same
services.minio = {
  enable = true;
  dataDir = [ "/var/lib/minio/data" ];
  rootCredentialsFile = "/persist/etc/secrets/animus-minio-credentials";
};

  services.animus = {
    enable = true;
    envFile = /persist/etc/secrets/animus.env;
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # --- Needed for boot stuff ---
  fileSystems."/persist".neededForBoot = true;

  # --- Bootloader ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostId = "b4dc0ff3";
  networking.firewall.allowedTCPPorts = [
    80
    443
    9000 
    9001
    5432 
  ];

  # --- ZFS Tweaks ---
  boot.zfs.forceImportRoot = true;

  # This copies the key from /persist into the initrd at build time
  boot.initrd.secrets = {
    "/data_drive.key" = "/persist/etc/secrets/data_drive.key";
  };

  # CRITICAL: Open the firewall ONLY for Tailscale, so the public internet can't use my AI
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 11434 ];

  # This ensures the data drive doesn't stop the boot if the key isn't ready.
  # The system will continue and try to unlock it again in Stage 2.
  boot.initrd.luks.devices."crypted_data" = {
    keyFile = lib.mkForce "/data_drive.key";
    keyFileSize = lib.mkForce 2048;
  };

  # --- The Impermanence Wipe ---
  # This triggers the ZFS rollback to the clean slate every we boot
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

  # --- Initrd SSH (The Fort Knox Early-Boot Unlock) ---
  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      port = 2222;
      authorizedKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID1qzN7jOZSdb2ppgP+ldtvxKt5ielBVcS6g+cbRa/lG angemmanuel.kouakou+professional@gmail.com"
      ];
      # Points to the key safely stored in your permanent dataset
      hostKeys = [ "/persist/etc/secrets/initrd/ssh_host_ed25519_key" ];
    };
  };

  # Required by NixOS to allow unlocking drives via SSH
  boot.initrd.systemd.enable = true;

  # Tailscale
  services.tailscale.enable = true;
  # --- Main System SSH Server ---
  services.openssh = {
    enable = true;
    # Disable passwords, enforce SSH key login only for maximum security
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "prohibit-password";
  };

  # Enable docker
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      data-root = "/mnt/data/docker";
    };
  };

  users.users = {
    root = {
      hashedPasswordFile = "/persist/etc/secrets/root-password";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID1qzN7jOZSdb2ppgP+ldtvxKt5ielBVcS6g+cbRa/lG angemmanuel.kouakou+professional@gmail.com"
      ];
    };
    user = {
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
  };

  # --- Impermanence Persistent State ---
  # Tells the system which files MUST survive the reboot wipe
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/log"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/var/lib/tailscale"
      "/home/user/"
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
  };

  # Standard packages
  environment.systemPackages = with pkgs; [
    postgres_17
    chromium
    vim
    git
    wget

    # Utilities
    nh

    # AI
    llama-cpp
  ];

  systemd.services.deepseek-server = {
    description = "DeepSeek Speculative Decoding API Server";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network.target"
      "tailscaled.service"
    ];

    serviceConfig = {
      # The command that runs the server
      ExecStart = ''
        ${pkgs.llama-cpp}/bin/llama-server \
          -m /mnt/data/models/Qwen2.5-Coder-3B-Instruct-Q8_0.gguf \
          --host 0.0.0.0 --port 11434 --threads 4 \
          -c 8192 \
          -np 2 \
          --alias qwen \
          --chat-template chatml \
          --no-mmap \
          --batch-size 128 \
          --ctx-size 8192 \
          --cont-batching
      '';
      Restart = "always";
      User = "user";
      WorkingDirectory = "/mnt/data/models";
    };
  };

  # Leave this matching the version of your install media (e.g., "23.11" or "24.05")
  system.stateVersion = "25.11";
}
