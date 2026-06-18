{ config, lib, pkgs, openshell-pkg, ... }:

let
  cfg = config.services.openshell;
  openshell-cli = openshell-pkg.openshell-cli;
  openshell-gateway = openshell-pkg.openshell-gateway;

  # Generate a unique gateway ID per-host
  gatewayId = "openshell-${config.networking.hostName}";
  dataDir = "/var/lib/openshell";
  configDir = "${dataDir}/gateway";
  keysDir = "${dataDir}/keys";
in
{
  options.services.openshell = {
    enable = lib.mkEnableOption "OpenShell — sandbox runtime for AI agents";

    gatewayPort = lib.mkOption {
      type = lib.types.port;
      default = 8082;
      description = "Port for the OpenShell gateway gRPC API";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ openshell-cli openshell-gateway ];

    # Create state directories
    systemd.tmpfiles.rules = [
      "d ${dataDir} 0755 root root -"
      "d ${configDir} 0755 root root -"
      "d ${keysDir} 0700 root root -"
    ];

    # Write gateway config
    environment.etc."openshell/gateway.toml".text = ''
      [openshell]
      version = 1

      [openshell.gateway]
      bind_address        = "127.0.0.1:${toString cfg.gatewayPort}"
      health_bind_address = "127.0.0.1:${toString (cfg.gatewayPort + 1)}"
      log_level           = "info"
      compute_drivers     = ["docker"]
      disable_tls         = true

      [openshell.drivers.docker]
      default_image     = "ghcr.io/nvidia/openshell-community/sandboxes/base:latest"
      supervisor_image  = "ghcr.io/nvidia/openshell/supervisor:latest"
      image_pull_policy = "IfNotPresent"
      sandbox_namespace = "openshell"
      grpc_endpoint     = "http://host.openshell.internal:${toString cfg.gatewayPort}"
    '';

    # Run the gateway as a native systemd service
    systemd.services.openshell-gateway = {
      description = "OpenShell sandbox gateway";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "docker.service" ];
      wants = [ "network-online.target" ];

      preStart = ''
        # Generate mTLS + JWT certs on first start if they don't exist
        CERT_DIR="${configDir}/gateways/${gatewayId}"
        if [ ! -f "$CERT_DIR/ca.crt" ]; then
          mkdir -p "$CERT_DIR"
          ${openshell-gateway}/bin/openshell-gateway generate-certs \
            --output-dir "$CERT_DIR" 2>/dev/null || true
        fi

        # Copy CLI certs to root's config for CLI auto-discovery
        CLI_DIR="/root/.config/openshell/gateways/${gatewayId}"
        mkdir -p "$CLI_DIR"
        for f in ca.crt client.crt client.key; do
          if [ -f "$CERT_DIR/$f" ] && [ ! -f "$CLI_DIR/$f" ]; then
            cp "$CERT_DIR/$f" "$CLI_DIR/$f"
          fi
        done
      '';

      serviceConfig = {
        Type = "simple";
        ExecStart = "${openshell-gateway}/bin/openshell-gateway \
          --config /etc/openshell/gateway.toml";
        Restart = "on-failure";
        RestartSec = "5s";
        TimeoutStartSec = "30";
      };
    };
  };
}
