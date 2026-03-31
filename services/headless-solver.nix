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

      apify-fingerprint-datapoints = mk {
        pname = "apify_fingerprint_datapoints"; 
        version = "0.11.0";
        hash = "sha256-P5BcOSsRon+1nM/kCJHBZqvXN6ucYglzPxAruzswJRU="; 
        backend = "hatch";
      };

      browserforge  = mk { 
        pname = "browserforge";  
        version = "1.2.4";  
        hash = "sha256-BWhkc3k3aYVuvTUoxpBx9b4OURJgmT6LK6g5hjcRoMQ="; 
        backend = "poetry";
        extraDeps = [ apify-fingerprint-datapoints ps.click ];
      };

      language-tags = mk { 
        pname = "language_tags"; 
        version = "1.2.0";  
        hash = "sha256-6TSsuj49yF+GdwPspCGEepq3t2ebEbXVz9CW/rv4veY="; 
      };
      
      screeninfo    = mk { pname = "screeninfo";    version = "0.8.1";  hash = "sha256-mYMHa8x+NEAqGp5NfavzcpQR/Sq7PztL5+unNRnNLtE="; backend = "poetry"; };
      
      ua-parser-builtins = ps.buildPythonPackage rec {
        pname = "ua_parser_builtins";
        version = "202603";
        format = "wheel";
        src = ps.fetchPypi {
          inherit pname version format;
          hash = "sha256-Z0eDl6aPrBqY/QoxxBbqfGWnGRQfwVHQIRMW8s0zfMk=";
          dist = "py3";
          python = "py3";
        };
      };

      ua-parser     = mk { 
        pname = "ua_parser";     
        version = "1.0.1";  
        hash = "sha256-+dkr8Z1DKQGc75FweuzCPG1lFDrX4pojPwWA+w0VVH0="; 
        extraDeps = [ ua-parser-builtins ];
        extraNativeBuildInputs = [ ps.setuptools-scm ps.pyyaml ];
      };
      
      tld           = mk { pname = "tld";           version = "0.13.2"; hash = "sha256-2YP6krnXF0AHQvyoROKdXhgnEHnHvPq/ZtAbObShQ0U="; extraNativeBuildInputs = [ ps.setuptools-scm ]; };
      w3lib         = mk { pname = "w3lib";         version = "2.4.1";  hash = "sha256-jdae45/2OY1wjHk6vHecM0ppusfO4c33FzbGae1r6GQ="; backend = "hatch"; };

      # NEW: Patchright package definition
      patchright    = mk {
        pname = "patchright";
        version = "1.58.2";
        hash = "sha256-7kXvPqN6B7L3B2A1C9D8E7F0RInLpZfKstP6r7XzI9u=";
      };

      scrapling = ps.buildPythonPackage rec {
        pname = "scrapling";
        version = "0.4.2";
        pyproject = true;
        src = ps.fetchPypi { inherit pname version; hash = "sha256-uqrEK98Er00+kRPY9QR3evV3QBS4cgjG1Ep773ro0fg="; };
        nativeBuildInputs = with ps; [ setuptools ];
        propagatedBuildInputs = with ps; [
          httpx playwright lxml cssselect orjson tldextract
          tld w3lib msgspec anyio curl-cffi patchright # Added patchright here
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
          browserforge language-tags screeninfo ua-parser orjson
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
      ExecStartPre = pkgs.writeShellScript "camoufox-conditional-fetch" ''
        if [ ! -d "/var/lib/camoufox/bin" ]; then
          ${solverPython}/bin/python -m camoufox fetch
        fi
        
        # Fetch Patchright browsers if missing
        # Patchright usually stores things in ~/.cache/ms-playwright or a custom path
        # We should point it to our state directory too
        if [ ! -d "/var/lib/camoufox/patchright" ]; then
          echo "Fetching Patchright browsers..."
          XDG_CACHE_HOME=/var/lib/camoufox ${solverPython}/bin/python -m patchright install chromium
        fi
      '';
      ExecStart = startScript;
      Restart = "always";
      RestartSec = 5;
      StateDirectory = "camoufox";
      Environment = [
        "PORT=8000"
        "SOLVER_URL=http://localhost:8000"
        "VAULT_PATH=/mnt/data/swagwatch-engine/vault"
        "CAMOUFOX_DIR=/var/lib/camoufox"
        "CAMOUFOX_SKIP_UPDATE=1"
        # Tell Patchright/Playwright to look in our StateDirectory
        "PLAYWRIGHT_BROWSERS_PATH=/var/lib/camoufox/patchright"
      ];
    };
  };
}
