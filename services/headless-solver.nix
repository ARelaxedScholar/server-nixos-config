{ config, lib, pkgs, ... }:

let
  # Override nixpkgs python packages that are too old for scrapling
  pyOverrides = pkgs.python3.override {
    packageOverrides = self: super: {
      cssselect = super.cssselect.overridePythonAttrs (_: {
        version = "1.4.0";
        pyproject = true;
        src = self.fetchPypi {
          pname = "cssselect";
          version = "1.4.0";
          hash = "sha256-/a8KFCXhff6MXPZhkdIRs1fPeHKuivxMZ2Ld2KxH/JI=";
        };
        nativeBuildInputs = [ self.hatchling ];
      });

      orjson = super.orjson.overridePythonAttrs (oldAttrs: rec {
        version = "3.11.7";
        pyproject = true;
        src = self.fetchPypi {
          pname = "orjson";
          version = "3.11.7";
          hash = "sha256-mxpnJDlFgZzlXSSjC1nWoWjoYiBFLSyW9NHwk+ccDEk=";
        };
        # Using fetchCargoVendor as required by NixOS 25.05+
        cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
          inherit src;
          hash = "sha256-eB7jVTsvBSUjtaKsbRnRtYSd+SqnCaoDyG76iExmSHc=";
        };
      });
    };
  };

  # Packages not in nixpkgs — built manually
  mkPkg = ps: { pname, version, hash, backend ? "setuptools", extraDeps ? [], extraNativeBuildInputs ? [] }:
    ps.buildPythonPackage {
      inherit pname version;
      pyproject = true;
      src = ps.fetchPypi { inherit pname version hash; };
      nativeBuildInputs = with ps;
        (if backend == "poetry" then [ poetry-core ] 
        else if backend == "hatch" then [ hatchling ]
        else [ setuptools ]) ++ extraNativeBuildInputs;
      propagatedBuildInputs = extraDeps;
      doCheck = false;
    };

  solverPython = pyOverrides.withPackages (ps:
    let
      mk = args: mkPkg ps args;

      # NEW: Dependency for browserforge
      apify-fingerprint-datapoints = mk {
        pname = "apify-fingerprint-datapoints";
        version = "0.11.0";
        hash = "sha256-P5BcOStRov+1XM/6CcEWZqvXN6vGIJN/GmqRFzYvNRU=";
      };

      # FIXED: Added backend and missing runtime dependencies (click + apify)
      browserforge  = mk { 
        pname = "browserforge";  
        version = "1.2.4";  
        hash = "sha256-BWhkc3k3aYVuvTUoxpBx9b4OURJgmT6LK6g5hjcRoMQ="; 
        backend = "poetry";
        extraDeps = [ apify-fingerprint-datapoints ps.click ];
      };

      language-tags = mk { pname = "language-tags"; version = "1.2.0";  hash = "sha256-6TSsuj49yF+GdwPspCGEepq3t2ebEbXVz9CW/rv4veY="; };
      screeninfo    = mk { pname = "screeninfo";    version = "0.8.1";  hash = "sha256-mYMHa8x+NEAqGp5NfavzcpQR/Sq7PztL5+unNRnNLtE="; backend = "poetry"; };
      ua-parser     = mk { pname = "ua-parser";     version = "1.0.1";  hash = "sha256-+dkr8Z1DKQGc75FweuzCPG1lFDrX4pojPwWA+w0VVH0="; };
      tld           = mk { pname = "tld";           version = "0.13.2"; hash = "sha256-2YP6krnXF0AHQvyoROKdXhgnEHnHvPq/ZtAbObShQ0U="; extraNativeBuildInputs = [ ps.setuptools-scm ]; };
      w3lib         = mk { pname = "w3lib";         version = "2.4.1";  hash = "sha256-jdae45/2OY1wjHk6vHecM0ppusfO4c33FzbGae1r6GQ="; backend = "hatch"; };

      scrapling = ps.buildPythonPackage rec {
        pname = "scrapling";
        version = "0.4.2";
        pyproject = true;
        src = ps.fetchPypi { inherit pname version; hash = "sha256-uqrEK98Er00+kRPY9QR3evV3QBS4cgjG1Ep773ro0fg="; };
        nativeBuildInputs = with ps; [ setuptools ];
        # Added msgspec and anyio which are required by modern Scrapling
        propagatedBuildInputs = with ps; [
          httpx playwright lxml cssselect orjson tldextract
          tld w3lib msgspec anyio
        ];
        doCheck = false;
      };

      camoufox = ps.buildPythonPackage rec {
        pname = "camoufox";
        version = "0.4.11";
        pyproject = true;
        src = ps.fetchPypi { inherit pname version; hash = "sha256-CiydJKxQcMEE58KxJcCjk39w76QWCE74iv6Uwypy7r4="; };
        nativeBuildInputs = with ps; [ poetry-core ];
        propagatedBuildInputs = with ps;
        [
          playwright typing-extensions lxml numpy platformdirs
          pysocks pyyaml requests tqdm
          browserforge language-tags screeninfo ua-parser
        ];
        doCheck = false;
      };

    in with ps; [
      scrapling
      camoufox
      fastapi
      uvicorn
      httpx
    ]
  );

  fetchScript = pkgs.writeShellScript "swagwatch-solver-fetch" ''
    exec ${solverPython}/bin/python -m camoufox fetch
  '';

  startScript = pkgs.writeShellScript "swagwatch-solver-start" ''
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
      ExecStartPre = fetchScript;
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
