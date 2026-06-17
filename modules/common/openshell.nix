{ config, lib, pkgs, openshell-pkg, ... }:

let
  cfg = config.services.openshell;
  openshell = openshell-pkg;
in
{
  options.services.openshell = {
    enable = lib.mkEnableOption "OpenShell — sandbox runtime for AI agents";

    gatewayPort = lib.mkOption {
      type = lib.types.port;
      default = 8082;
      description = "Host port for the OpenShell gateway gRPC API";
    };

    healthPort = lib.mkOption {
      type = lib.types.port;
      default = 8083;
      description = "Host port for the OpenShell health endpoint";
    };
  };

  config = lib.mkIf cfg.enable {
    # Install the openshell binary system-wide
    environment.systemPackages = [ openshell ];

    # Create /var/lib/openshell for the gateway data directory
    systemd.tmpfiles.rules = [
      "d /var/lib/openshell 0755 root root -"
      "d /var/lib/openshell/keys 0700 root root -"
    ];

    # Write the gateway config
    environment.etc."openshell/gateway.toml".text = ''
      [openshell]
      version = 1

      [openshell.gateway]
      bind_address        = "127.0.0.1:8080"
      health_bind_address = "127.0.0.1:8081"
      log_level           = "info"
      compute_drivers     = ["docker"]
      disable_tls         = true

      [openshell.drivers.docker]
      default_image     = "ghcr.io/nvidia/openshell-community/sandboxes/base:latest"
      supervisor_image  = "ghcr.io/nvidia/openshell/supervisor:latest"
      image_pull_policy = "IfNotPresent"
      sandbox_namespace = "openshell"
      grpc_endpoint     = "http://host.openshell.internal:8080"
    '';

    # Run the OpenShell gateway as a Docker container via the docker-compose.yml
    # managed by the openshell CLI.
    # The gateway container is started via the openshell CLI's docker integration.
  };
}
