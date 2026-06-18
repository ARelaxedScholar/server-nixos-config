{ pkgs, lib, ... }:

let
  version = "0.0.65";
  system = pkgs.stdenv.hostPlatform.system;
  arch = if system == "x86_64-linux" then "x86_64" else "aarch64";
in
{
  openshell-cli = pkgs.stdenv.mkDerivation {
    pname = "openshell";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/NVIDIA/OpenShell/releases/download/v${version}/openshell-${arch}-unknown-linux-musl.tar.gz";
      sha256 = "3d113b9c29a71004cdf0fc7fcb9c7c07efa2e27c9faca83d191ebb8e5ad88392";
    };

    dontBuild = true;
    dontConfigure = true;
    dontUnpack = true;

    installPhase = ''
      mkdir -p $out/bin
      tar xzf $src -C $out/bin openshell
      chmod +x $out/bin/openshell
    '';

    meta = with lib; {
      description = "OpenShell CLI — sandbox runtime for autonomous AI agents";
      homepage = "https://github.com/NVIDIA/OpenShell";
      license = licenses.asl20;
      platforms = [ "x86_64-linux" "aarch64-linux" ];
    };
  };

  openshell-gateway = pkgs.stdenv.mkDerivation {
    pname = "openshell-gateway";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/NVIDIA/OpenShell/releases/download/v${version}/openshell-gateway-${arch}-unknown-linux-gnu.tar.gz";
      sha256 = "d5ab49a9a68390a2fb87108215252cd2d1f4004bbeb6fe45897f260385c422c1";
    };

    dontBuild = true;
    dontConfigure = true;
    dontUnpack = true;

    installPhase = ''
      mkdir -p $out/bin
      tar xzf $src -C $out/bin openshell-gateway
      chmod +x $out/bin/openshell-gateway
    '';

    meta = with lib; {
      description = "OpenShell gateway server — sandbox runtime for autonomous AI agents";
      homepage = "https://github.com/NVIDIA/OpenShell";
      license = licenses.asl20;
      platforms = [ "x86_64-linux" "aarch64-linux" ];
    };
  };
}
