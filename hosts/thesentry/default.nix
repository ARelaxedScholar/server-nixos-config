{ ... }:
let
  serverRoot = "/home/user/server";
  dockerSocketMount = "/run/docker.sock:/var/run/docker.sock";
  obsidianLiveSyncEnvFile = "${serverRoot}/obsidian-livesync/couchdb.env";
in
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
  ];

  networking.hostName = "thesentry";
  networking.hostId = "9a4c2f17";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.systemd.enable = true;
  boot.zfs.forceImportRoot = true;

  # This host is a laptop, but it must behave like an always-on server.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleSuspendKey = "ignore";
    HandleHibernateKey = "ignore";
    HandleHybridSleepKey = "ignore";
    IdleAction = "ignore";
  };

  systemd.sleep.extraConfig = ''
    AllowSuspend=no
    AllowHibernation=no
    AllowHybridSleep=no
    AllowSuspendThenHibernate=no
  '';

  services.tailscale.enable = true;

  users.users.user = {
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID1qzN7jOZSdb2ppgP+ldtvxKt5ielBVcS6g+cbRa/lG angemmanuel.kouakou+professional@gmail.com"
    ];
    extraGroups = [
      "wheel"
      "podman"
    ];
  };

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    dockerSocket.enable = true;
    autoPrune.enable = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      "nginx-proxy-manager" = {
        image = "docker.io/jc21/nginx-proxy-manager:latest";
        ports = [ "80:80" "443:443" "81:81" ];
        volumes = [
          "${serverRoot}/npm/data:/data"
          "${serverRoot}/npm/letsencrypt:/etc/letsencrypt"
        ];
      };

      homepage = {
        image = "ghcr.io/gethomepage/homepage:latest";
        ports = [ "8000:3000" ];
        volumes = [
          "${serverRoot}/homepage:/app/config"
          dockerSocketMount
        ];
      };

      immich_server = {
        image = "ghcr.io/immich-app/immich-server:release";
        dependsOn = [ "immich_postgres" "immich_redis" ];
        ports = [ "2283:2283" ];
        environment = {
          DB_HOSTNAME = "immich_postgres";
          REDIS_HOSTNAME = "immich_redis";
        };
        volumes = [
          "${serverRoot}/immich/photos:/usr/src/app/upload"
          "/etc/localtime:/etc/localtime:ro"
        ];
        extraOptions = [ "--memory=4g" ];
      };

      freshrss = {
        image = "docker.io/freshrss/freshrss:latest";
        ports = [ "8082:80" ];
        volumes = [
          "${serverRoot}/freshrss:/var/www/FreshRSS/data"
        ];
      };

      changedetection = {
        image = "ghcr.io/dgtlmoon/changedetection.io:latest";
        ports = [ "5000:5000" ];
        volumes = [
          "${serverRoot}/changedetection:/datastore"
        ];
        extraOptions = [ "--memory=1g" ];
      };

      forgejo = {
        image = "codeberg.org/forgejo/forgejo:14.0.2";
        ports = [ "3000:3000" ];
        volumes = [
          "${serverRoot}/forgejo:/data"
        ];
      };

      # Obsidian LiveSync only needs plain CouchDB here; nginx-proxy-manager should
      # terminate HTTPS in front of it. This service intentionally depends on a
      # host-side env file so it fails closed until you add real credentials.
      obsidian_livesync = {
        image = "docker.io/library/couchdb:3";
        ports = [ "5984:5984" ];
        volumes = [
          "${serverRoot}/obsidian-livesync/data:/opt/couchdb/data"
        ];
        extraOptions = [
          "--env-file=${obsidianLiveSyncEnvFile}"
        ];
      };

      searxng = {
        image = "docker.io/searxng/searxng:latest";
        dependsOn = [ "searxng_redis" ];
        ports = [ "8081:8080" ];
        volumes = [
          "${serverRoot}/searxng:/etc/searxng"
        ];
      };

      searxng_redis = {
        image = "docker.io/library/redis:alpine";
      };

      lute = {
        image = "docker.io/jzohrab/lute3:latest";
        ports = [ "5003:5001" ];
        volumes = [
          "${serverRoot}/lute/data:/lute_data"
          "${serverRoot}/lute/backups:/lute_backup"
        ];
      };

      navidrome = {
        image = "docker.io/deluan/navidrome:latest";
        ports = [ "4533:4533" ];
        volumes = [
          "${serverRoot}/navidrome/data:/data"
          "${serverRoot}/music:/music:ro"
        ];
      };

      immich_postgres = {
        image = "docker.io/tensorchord/pgvecto-rs:pg16-v0.2.0";
        environment = {
          POSTGRES_PASSWORD = "postgres";
          POSTGRES_USER = "postgres";
          POSTGRES_DB = "immich";
        };
        volumes = [
          "${serverRoot}/immich/db:/var/lib/postgresql/data"
        ];
      };

      immich_redis = {
        image = "docker.io/library/redis:6.2-alpine";
      };
    };
  };
}
