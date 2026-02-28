{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Imports hardware specifics and the Disko storage layout
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
  ];
  # --- Needed for boot stuff ---
  fileSystems."/persist".neededForBoot = true;

  # --- Bootloader ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostId = "b4dc0ff3";

  # --- ZFS Tweaks ---
  boot.zfs.forceImportRoot = true;

  # This ensures the data drive doesn't stop the boot if the key isn't ready.
  # The system will continue and try to unlock it again in Stage 2.
  boot.initrd.luks.devices."crypted_data" = {
    keyFile = lib.mkForce "/persist/etc/secrets/data_drive.key";
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

  # --- Main System SSH Server ---
  services.openssh = {
    enable = true;
    # Disable passwords, enforce SSH key login only for maximum security
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "prohibit-password";
  };

  # Enable docker
  virtualisation.docker.enable = true;
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
      "/var/lib/docker"
      "/var/lib/tailscale"
      "/home/user/server-nixos-config" 
      "/home/user/.ssh" 
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
    vim
    git
    wget
    
    # Utilities
    nh
  ];

  # Leave this matching the version of your install media (e.g., "23.11" or "24.05")
  system.stateVersion = "25.11";
}
