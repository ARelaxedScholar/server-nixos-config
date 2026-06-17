{ pkgs, lib, ... }:

let
  version = "0.0.65";
  sha256 = "3d113b9c29a71004cdf0fc7fcb9c7c07efa2e27c9faca83d191ebb8e5ad88392";
  system = pkgs.stdenv.hostPlatform.system;
  arch = if system == "x86_64-linux" then "x86_64" else "aarch64";
in
pkgs.stdenv.mkDerivation {
  pname = "openshell";
  inherit version;

  src = pkgs.fetchurl {
    url = "https://github.com/NVIDIA/OpenShell/releases/download/v${version}/openshell-${arch}-unknown-linux-musl.tar.gz";
    inherit sha256;
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
    description = "Safe, private runtime for autonomous AI agents";
    homepage = "https://github.com/NVIDIA/OpenShell";
    license = licenses.asl20;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    maintainers = [ ];
  };
}
