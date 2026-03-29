{ config, lib, pkgs, ... }:

let
  # Build the Python environment with all solver dependencies
  solverPython = pkgs.python3.withPackages (ps: with ps; [
    # Core scraping stack
    (ps.buildPythonPackage rec {
      pname = "scrapling";
      version = "0.4.2";
      format = "pyproject";
      src = ps.fetchPypi {
        inherit pname version;
        hash = "sha256-uqrEK98Er00+kRPY9QR3evV3QBS4cgjG1Ep773ro0fg="; # fill in after first build
      };
      propagatedBuildInputs = with ps; [
        httpx playwright lxml cssselect orjson tldextract
      ];
      doCheck = false;
    })
    (ps.buildPythonPackage rec {
      pname = "camoufox";
      version = "0.4.11"; # pin to your tested version
      format = "pyproject";
      src = ps.fetchPypi {
        inherit pname version;
        hash = "sha256-CiydJKxQcMEE58KxJcCjk39w76QWCE74iv6Uwypy7r4="; # fill in after first build
      };
      nativeBuildInputs = with ps; [
        poetry-core  
        setuptools
      ];
      propagatedBuildInputs = with ps; [
        playwright browserforge typing-extensions
      ];
      doCheck = false;
    })
    # Add any other deps from your requirements.txt here
    fastapi uvicorn httpx
  ]);

  # Pre-fetch the Camoufox Firefox binary into the Nix store
  # Run `nix-prefetch-url --unpack <url>` to get the hash
  camoufoxBrowser = pkgs.fetchzip {
    url = "https://github.com/daijro/camoufox/releases/download/v0.4.11/camoufox-linux.tar.gz"; # adjust version/arch
    hash = "sha256-CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC="; # fill in
  };

  # Wrapper script that points Camoufox at the pre-fetched binary
  startScript = pkgs.writeShellScript "swagwatch-solver-start" ''
    export CAMOUFOX_EXECUTABLE="${camoufoxBrowser}/camoufox";
    exec ${solverPython}/bin/python /mnt/data/swagwatch-engine/solver/main.py
  '';

in
{
  systemd.services.swagwatch-solver = {
    description = "SwagWatch Headless Solver (Scrapling + Camoufox)";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      User = "user";
      WorkingDirectory = "/mnt/data/swagwatch-engine";
      ExecStart = startScript;
      Restart = "always";
      RestartSec = 5;
      Environment = [
        "PORT=8000"
        "SOLVER_URL=http://localhost:8000"
        "VAULT_PATH=/mnt/data/swagwatch-engine/vault"
      ];
    };
  };
}
