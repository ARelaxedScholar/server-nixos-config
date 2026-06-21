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
  sandboxNames = [
    "uriel"
    "midas"
    "musa"
  ];
  persistentRoot = "/persist/openshell";

  mkSandboxSpec = name: {
    template = {
      image = "ghcr.io/nvidia/openshell-community/sandboxes/base:latest";
      # Make the durable host workspace visible inside the disposable sandbox.
      # OpenShell's Docker driver deliberately forbids replacing /sandbox itself,
      # so /sandbox/workspace is the persistent root agents should use.
      driverConfig = {
        docker = {
          mounts = [
            {
              type = "bind";
              source = "${persistentRoot}/${name}/workspace";
              target = "/sandbox/workspace";
              read_only = false;
            }
          ];
        };
      };
    };
    logLevel = "info";
    policy = {
      version = 1;
      landlock = {
        compatibility = "best_effort";
      };
      filesystem = {
        includeWorkdir = true;
        readOnly = [
          "/usr" "/lib" "/lib64" "/proc"
          "/dev/urandom" "/dev/random"
          "/app" "/etc" "/var/log"
          "/bin" "/sbin" "/opt/openshell"
        ];
        readWrite = [
          "/sandbox" "/sandbox/workspace" "/tmp" "/var/tmp" "/home/sandbox" "/nix"
          "/dev/null" "/dev/zero" "/dev/pts"
        ];
      };
      process = {
        runAsUser = "sandbox";
        runAsGroup = "sandbox";
      };
      networkPolicies = {
        default_egress = {
          name = "agent-default-egress";
          endpoints = [
            { host = "**.openrouter.ai"; port = 443; enforcement = "audit"; access = "full"; ports = [ 443 ]; }
            { host = "**.anthropic.com"; port = 443; enforcement = "audit"; access = "full"; ports = [ 443 ]; }
            { host = "**.openai.com"; port = 443; enforcement = "audit"; access = "full"; ports = [ 443 ]; }
            { host = "**.github.com"; port = 443; enforcement = "audit"; access = "full"; ports = [ 443 ]; }
            { host = "**.githubusercontent.com"; port = 443; enforcement = "audit"; access = "full"; ports = [ 443 ]; }
            { host = "pypi.org"; port = 443; enforcement = "audit"; access = "full"; ports = [ 443 ]; }
            { host = "files.pythonhosted.org"; port = 443; enforcement = "audit"; access = "full"; ports = [ 443 ]; }
            { host = "**.npmjs.org"; port = 443; enforcement = "audit"; access = "full"; ports = [ 443 ]; }
            { host = "**.crates.io"; port = 443; enforcement = "audit"; access = "full"; ports = [ 443 ]; }
            { host = "**.rust-lang.org"; port = 443; enforcement = "audit"; access = "full"; ports = [ 443 ]; }
            { host = "ghcr.io"; port = 443; enforcement = "audit"; access = "full"; ports = [ 443 ]; }
            { host = "gitlab.com"; port = 443; enforcement = "audit"; access = "full"; ports = [ 443 ]; }
            { host = "cache.nixos.org"; port = 443; enforcement = "audit"; access = "full"; ports = [ 443 ]; }
            { host = "releases.nixos.org"; port = 443; enforcement = "audit"; access = "full"; ports = [ 443 ]; }
            { host = "channels.nixos.org"; port = 443; enforcement = "audit"; access = "full"; ports = [ 443 ]; }
            { host = "**.cachix.org"; port = 443; enforcement = "audit"; access = "full"; ports = [ 443 ]; }
            { host = "host.openshell.internal"; port = 8082; enforcement = "audit"; access = "full"; ports = [ 8082 ]; }
          ];
          binaries = [
            { path = "/bin/bash"; } { path = "/bin/sh"; }
            { path = "/usr/bin/curl"; } { path = "/usr/bin/wget"; }
            { path = "/usr/bin/git"; } { path = "/usr/bin/python3"; }
            { path = "/usr/local/bin/uv"; }
            { path = "/sandbox/.local/bin/**"; } { path = "/home/sandbox/.local/bin/**"; }
            { path = "/sandbox/.venv/**"; } { path = "/home/sandbox/.venv/**"; }
            { path = "/usr/bin/make"; } { path = "/usr/bin/cargo"; }
            { path = "/sandbox/**"; }
            { path = "/nix/**"; }
          ];
        };
      };
    };
  };
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
    environment.systemPackages = [ openshell-cli openshell-gateway pkgs.grpcurl ];

    # Create state directories
    systemd.tmpfiles.rules = [
      "d ${dataDir} 0755 root root -"
      "d ${configDir} 0755 root root -"
      "d ${keysDir} 0700 root root -"
      "d ${persistentRoot} 0755 root root -"
    ] ++ (map (name: "d ${persistentRoot}/${name} 0755 root root -") sandboxNames)
      # Owner uid 998 is the sandbox user in the base image.  Group users keeps
      # the host login user able to inspect/edit persisted work without making
      # the workspace world-writable.
      ++ (map (name: "d ${persistentRoot}/${name}/workspace 0775 998 users -") sandboxNames);

    # Write gateway config and sandbox creation templates.
    environment.etc = {
      "openshell/gateway.toml".text = ''
      [openshell]
      version = 1

      [openshell.gateway]
      bind_address        = "127.0.0.1:${toString cfg.gatewayPort}"
      health_bind_address = "127.0.0.1:${toString (cfg.gatewayPort + 1)}"
      log_level           = "info"
      compute_drivers     = ["docker"]

      [openshell.gateway.auth]
      allow_unauthenticated_users = true

      [openshell.gateway.gateway_jwt]
      signing_key_path = "${keysDir}/signing.pem"
      public_key_path  = "${keysDir}/public.pem"
      kid_path         = "${keysDir}/kid"
      gateway_id       = "${gatewayId}"
      ttl_secs         = 3600

      [openshell.drivers.docker]
      default_image     = "ghcr.io/nvidia/openshell-community/sandboxes/base:latest"
      supervisor_image  = "ghcr.io/nvidia/openshell/supervisor:latest"
      image_pull_policy = "IfNotPresent"
      sandbox_namespace = "openshell"
      enable_bind_mounts = true

      # grpc_endpoint is intentionally omitted — the Docker driver
      # auto-detects http://host.openshell.internal:<gateway-port>
      # when TLS is disabled.
      '';
    } // builtins.listToAttrs (map (name: {
      name = "openshell/create-sandbox-${name}.json";
      value.text = builtins.toJSON {
        spec = mkSandboxSpec name;
        name = "${name}-sandbox";
      };
    }) sandboxNames);

    # Oneshot that reconnects or recreates the sandbox after gateway starts
    systemd.services.openshell-sandbox-setup = {
      description = "OpenShell sandbox lifecycle — reconnect or recreate after gateway restart";
      wantedBy = [ "multi-user.target" ];
      after = [ "openshell-gateway.service" "docker.service" ];
      wants = [ "openshell-gateway.service" ];
      before = [ "uriel.service" ];

      path = [ pkgs.grpcurl openshell-cli pkgs.docker pkgs.curl pkgs.gnugrep pkgs.sudo pkgs.coreutils pkgs.findutils ];

      script = ''
        set -euo pipefail
        GATEWAY="localhost:8082"
        PROTO_DIR="/tmp/openshell-proto-v0.0.65"
        SANDBOXES="${lib.concatStringsSep " " sandboxNames}"

        container_is_running() {
          container="$1"
          [ "$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null || true)" = "true" ]
        }

        provision_nix_in_sandbox() {
          sandbox="$1"
          container=$(docker ps --format '{{.Names}}' | grep -m1 "^openshell-$sandbox-sandbox-" || true)
          if [ -z "$container" ]; then
            echo "No Docker container found for OpenShell sandbox $sandbox; skipping Nix provisioning"
            return 0
          fi
          if ! container_is_running "$container"; then
            echo "OpenShell sandbox container $container is not running yet; skipping Nix provisioning this activation"
            return 0
          fi

          echo "Ensuring Nix is available inside $sandbox ($container)"
          docker exec "$container" bash -lc '
            set -euo pipefail
            export DEBIAN_FRONTEND=noninteractive
            missing_pkgs=""
            for cmd in nix sshd tar git gh curl ssh; do
              case "$cmd" in
                sshd) command -v /usr/sbin/sshd >/dev/null 2>&1 || missing_pkgs=1 ;;
                *) command -v "$cmd" >/dev/null 2>&1 || missing_pkgs=1 ;;
              esac
            done
            if [ -n "$missing_pkgs" ]; then
              apt-get update
              apt-get install -y --no-install-recommends nix-bin ca-certificates xz-utils openssh-server openssl tar git gh curl openssh-client
            fi
            # Nix requires /nix and its parents to be real paths, not symlinks.
            # Fresh sandboxes get a real writable /nix before first Nix use.
            # Existing sandboxes that already fell back to a chroot store under
            # /sandbox/.local/share/nix/root/nix get that root bind-mounted at
            # /nix so absolute builder paths like /nix/store/... resolve without
            # NIX_IGNORE_SYMLINK_STORE and without flake source canonicalization errors.
            if [ -L /nix ]; then
              rm /nix
            fi
            if [ ! -e /nix ]; then
              mkdir -p /nix
              chown sandbox:sandbox /nix
            fi
            if [ -d /sandbox/.local/share/nix/root/nix/store ]; then
              if ! mountpoint -q /nix; then
                # A plain empty /nix after sandbox reset must become a bind mount,
                # not a symlink.  Mounting over the empty directory is safe; if it
                # is not empty, leave it alone and fail loudly.
                if [ -z "$(ls -A /nix 2>/dev/null)" ] || [ -d /nix/store ]; then
                  mount --bind /sandbox/.local/share/nix/root/nix /nix
                else
                  echo "ERROR: /nix is not empty and is not a mountpoint; refusing to hide it" >&2
                  exit 1
                fi
              fi
            else
              mkdir -p /nix/store /nix/var/nix
              chown -R sandbox:sandbox /nix
            fi

            mkdir -p /etc/nix /etc/profile.d /sandbox/.config/nix /home/sandbox/.config/nix
            cat > /etc/nix/nix.conf <<EOF
experimental-features = nix-command flakes
sandbox = false
trusted-users = root sandbox
EOF
            cp /etc/nix/nix.conf /sandbox/.config/nix/nix.conf
            cp /etc/nix/nix.conf /home/sandbox/.config/nix/nix.conf
            cat > /etc/profile.d/nix-sandbox.sh <<'EOF'
# OpenShell sandbox Nix defaults.  Keep Nix usable from login shells,
# non-login shells, SSH sessions, and agent exec wrappers.
export NIX_CONFIG="experimental-features = nix-command flakes
sandbox = false"
export PATH="/usr/bin:/bin:/usr/local/bin:$PATH"
EOF
            grep -qxF '. /etc/profile.d/nix-sandbox.sh' /sandbox/.profile || echo '. /etc/profile.d/nix-sandbox.sh' >> /sandbox/.profile
            grep -qxF '. /etc/profile.d/nix-sandbox.sh' /sandbox/.bashrc || echo '. /etc/profile.d/nix-sandbox.sh' >> /sandbox/.bashrc
            grep -qxF '. /etc/profile.d/nix-sandbox.sh' /home/sandbox/.profile 2>/dev/null || echo '. /etc/profile.d/nix-sandbox.sh' >> /home/sandbox/.profile
            grep -qxF '. /etc/profile.d/nix-sandbox.sh' /home/sandbox/.bashrc 2>/dev/null || echo '. /etc/profile.d/nix-sandbox.sh' >> /home/sandbox/.bashrc
            chown -R sandbox:sandbox /sandbox/.config /home/sandbox/.config /sandbox/.profile /sandbox/.bashrc /home/sandbox/.profile /home/sandbox/.bashrc || true
            su -s /bin/bash sandbox -c "git config --global user.name \"OpenShell Sandbox\" && git config --global user.email \"sandbox@swagwatch-engine.local\""
            su -s /bin/bash sandbox -c "git config --global --add safe.directory /sandbox/workspace/Golden-Aegis || true"
            su -s /bin/bash sandbox -c "git config --global --add safe.directory /sandbox/Golden-Aegis || true"
            if [ -d /sandbox/workspace/Golden-Aegis ] && [ ! -e /sandbox/Golden-Aegis ]; then
              ln -s /sandbox/workspace/Golden-Aegis /sandbox/Golden-Aegis
              chown -h sandbox:sandbox /sandbox/Golden-Aegis || true
            fi
            nix --version
            su -s /bin/bash sandbox -c "export HOME=/sandbox; export USER=sandbox; . /etc/profile.d/nix-sandbox.sh; nix --version" >/dev/null
          '
        }

        restore_sandbox_state() {
          sandbox="$1"
          container=$(docker ps --format '{{.Names}}' | grep -m1 "^openshell-$sandbox-sandbox-" || true)
          if [ -z "$container" ]; then
            echo "No running container for $sandbox; skipping state restoration"
            return 0
          fi
          if ! container_is_running "$container"; then
            echo "OpenShell sandbox container $container is not running yet; skipping state restoration this activation"
            return 0
          fi

          echo "Configuring durable workspace mount and essential identity for $sandbox"
          docker exec "$container" sh -lc '
            set -euo pipefail
            mkdir -p /sandbox/workspace
            chown -R sandbox:sandbox /sandbox/workspace || true
          '

          # Restore /sandbox/.env from Hermes profile (always, overwrites any backup copy)
          env_src="/home/user/.hermes/profiles/$sandbox/.env"
          if [ -r "$env_src" ]; then
            docker cp "$env_src" "$container:/sandbox/.env"
            docker exec "$container" sh -lc 'chown sandbox:sandbox /sandbox/.env && chmod 600 /sandbox/.env'
            echo "Restored /sandbox/.env ($(wc -c < "$env_src") bytes)"
          else
            echo "No Hermes .env for $sandbox at $env_src; skipping"
          fi

          # Ensure SSH key auth is set up
          pubkey_path="/home/user/.hermes/profiles/$sandbox/ssh/id_ed25519_openshell.pub"
          if [ -r "$pubkey_path" ]; then
            docker exec "$container" bash -lc '
              set -euo pipefail
              mkdir -p /sandbox/.ssh
              chmod 700 /sandbox/.ssh
              touch /sandbox/.ssh/authorized_keys
              chmod 600 /sandbox/.ssh/authorized_keys
              chown -R sandbox:sandbox /sandbox/.ssh
              if command -v openssl >/dev/null 2>&1; then
                hash="$(openssl rand -base64 32 | openssl passwd -6 -stdin)"
                usermod -p "$hash" sandbox
              fi
              service ssh start >/dev/null 2>&1 || true
            '
            docker exec -i "$container" bash -lc '
              set -euo pipefail
              cat > /tmp/hermes-profile-key.pub
              grep -qxF -f /tmp/hermes-profile-key.pub /sandbox/.ssh/authorized_keys || cat /tmp/hermes-profile-key.pub >> /sandbox/.ssh/authorized_keys
              chown sandbox:sandbox /sandbox/.ssh/authorized_keys
              chmod 600 /sandbox/.ssh/authorized_keys
            ' < "$pubkey_path"
          fi
        }

        sandbox_recreate() {
          sandbox="$1"
          SBOX_NAME="$sandbox-sandbox"
          CREATE_JSON="/etc/openshell/create-sandbox-$sandbox.json"

          echo "Sandbox $SBOX_NAME is missing or stale — recreating"

          # Once /sandbox/workspace is a host bind mount, containers are disposable.
          # Do not try to tar/copy /sandbox on every recreate: the durable work
          # lives under ${persistentRoot}/<sandbox>/workspace on the host.
          container=$(docker ps -a --format '{{.Names}}' | grep -m1 "^openshell-$sandbox-sandbox-" || true)
          if [ -n "$container" ]; then
            echo "Found stale container $container; deleting through OpenShell before recreate"
          else
            echo "No container found for $sandbox; creating fresh sandbox"
          fi

          # Delete old registration (may fail), then remove any leftover Docker
          # container.  This is intentionally safe now that real work lives in
          # ${persistentRoot}/<sandbox>/workspace; it prevents the recurrent
          # post-reboot split-brain where Docker keeps a stale container whose
          # OpenShell JWT is no longer accepted by the gateway.
          grpcurl -plaintext \
            -proto "$PROTO_DIR/openshell.proto" \
            -import-path "$PROTO_DIR" \
            -d '{"name":"'$SBOX_NAME'"}' \
            "$GATEWAY" openshell.v1.OpenShell/DeleteSandbox 2>/dev/null || true
          if [ -n "$container" ]; then
            docker rm -f "$container" >/dev/null 2>&1 || true
          fi

          # Wait briefly for any stale state to clear
          sleep 2

          # Create with retry on AlreadyExists
          if [ -f "$CREATE_JSON" ]; then
            for attempt in 1 2 3; do
              echo "CreateSandbox attempt $attempt for $SBOX_NAME"
              output=$(grpcurl -plaintext -d @ \
                -proto "$PROTO_DIR/openshell.proto" \
                -import-path "$PROTO_DIR" \
                "$GATEWAY" openshell.v1.OpenShell/CreateSandbox < "$CREATE_JSON" 2>&1) && {
                echo "Sandbox $SBOX_NAME created with policy"
                return 0
              }
              if echo "$output" | grep -q "AlreadyExists"; then
                echo "Stale sandbox $SBOX_NAME — retrying delete"
                grpcurl -plaintext \
                  -proto "$PROTO_DIR/openshell.proto" \
                  -import-path "$PROTO_DIR" \
                  -d '{"name":"'$SBOX_NAME'"}' \
                  "$GATEWAY" openshell.v1.OpenShell/DeleteSandbox 2>/dev/null || true
                sleep 3
              else
                echo "Failed to create $SBOX_NAME: $output"
                return 1
              fi
            done
            echo "Exhausted retries for $SBOX_NAME"
            return 1
          else
            echo "No $CREATE_JSON found — sandbox will be created on demand"
            return 1
          fi
        }

        # Pull proto files if missing
        if [ ! -f "$PROTO_DIR/openshell.proto" ]; then
          mkdir -p "$PROTO_DIR"
          for name in openshell.proto sandbox.proto compute_driver.proto datamodel.proto; do
            curl -sL -o "$PROTO_DIR/$name" \
              "https://raw.githubusercontent.com/nvidia/openshell/v0.0.65/proto/$name"
          done
        fi

        for sandbox in $SANDBOXES; do
          SBOX_NAME="$sandbox-sandbox"

          # Check if sandbox exists and is healthy
          HEALTHY=$(grpcurl -plaintext \
            -proto "$PROTO_DIR/openshell.proto" \
            -import-path "$PROTO_DIR" \
            -d '{"name":"'$SBOX_NAME'"}' \
            "$GATEWAY" openshell.v1.OpenShell/GetSandbox 2>/dev/null \
            | grep -c '"SANDBOX_PHASE_READY"' || true)

          if [ "$HEALTHY" -gt 0 ]; then
            echo "Sandbox $SBOX_NAME is healthy — keeping it alive"
          else
            sandbox_recreate "$sandbox" || echo "WARNING: sandbox_recreate for $sandbox failed; continuing"
          fi

          # Wait for container to appear and reach Ready phase
          for i in $(seq 1 30); do
            phase=$(grpcurl -plaintext \
              -proto "$PROTO_DIR/openshell.proto" \
              -import-path "$PROTO_DIR" \
              -d '{"name":"'$SBOX_NAME'"}' \
              "$GATEWAY" openshell.v1.OpenShell/GetSandbox 2>/dev/null \
              | grep '"phase"' || true)
            if echo "$phase" | grep -q '"SANDBOX_PHASE_READY"'; then
              echo "$SBOX_NAME is READY"
              break
            fi
            if [ "$i" -eq 30 ]; then
              echo "WARNING: $SBOX_NAME did not reach READY within timeout; continuing"
            fi
            sleep 2
          done

          provision_nix_in_sandbox "$sandbox" || echo "WARNING: Nix provisioning for $sandbox failed; continuing"
          restore_sandbox_state "$sandbox" || echo "WARNING: state restoration for $sandbox failed; continuing"
        done


        # Register gateway for Uriel's CLI auto-discovery
        sudo -u uriel openshell gateway add http://localhost:8082 --name openshell 2>/dev/null || \
          sudo -u uriel openshell gateway select openshell 2>/dev/null || true
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    # Run the gateway as a native systemd service
    systemd.services.openshell-gateway = {
      description = "OpenShell sandbox gateway";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "docker.service" ];
      wants = [ "network-online.target" ];

      preStart = ''
        # The OpenShell Docker supervisor cache can be left corrupt across
        # reboots/interrupted extraction: the expected binary path becomes a
        # directory, causing every gateway start to fail with "Is a directory".
        # This cache is safe to delete; the gateway re-extracts it on start.
        if [ -d /root/.local/share/openshell/docker-supervisor ]; then
          find /root/.local/share/openshell/docker-supervisor \
            -mindepth 2 -maxdepth 2 -type d -name openshell-sandbox \
            -exec rm -rf {} +
        fi

        # Generate JWT signing keys on first boot
        KEYS_DIR="${keysDir}"
        mkdir -p "$KEYS_DIR"
        if [ ! -f "$KEYS_DIR/signing.pem" ]; then
          openssl genpkey -algorithm ed25519 -out "$KEYS_DIR/signing.pem"
          openssl pkey -in "$KEYS_DIR/signing.pem" -pubout -out "$KEYS_DIR/public.pem"
          openssl rand -hex 16 > "$KEYS_DIR/kid"
          chmod 600 "$KEYS_DIR"/*
        fi
      '';

      environment = {
        HOME = "/root";
      };

      path = [ pkgs.nix pkgs.openssl ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${openshell-gateway}/bin/openshell-gateway --config /etc/openshell/gateway.toml --disable-tls";
        Restart = "on-failure";
        RestartSec = "5s";
        TimeoutStartSec = "30";
      };
    };

  };
}

