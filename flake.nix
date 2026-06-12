{
  description = "Multi-host NixOS configuration for swagwatch-engine and thesentry";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko/latest";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    impermanence.url = "github:nix-community/impermanence";
    animus.url = "github:ARelaxedScholar/Animus";
    animus.inputs.nixpkgs.follows = "nixpkgs";
    swagwatch-engine.url = "git+file:///mnt/data/swagwatch-engine";
  };

  outputs =
    {
      nixpkgs,
      disko,
      impermanence,
      animus,
      swagwatch-engine,
      ...
    }@inputs:
    let
      mkHost =
        {
          modules,
          extraSpecialArgs ? { },
        }:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
          }
          // extraSpecialArgs;
          inherit modules;
        };
    in
    {
      nixosConfigurations = {
        swagwatch-engine = mkHost {
          extraSpecialArgs = { inherit animus swagwatch-engine; };
          modules = [
            ./modules/common/base.nix
            ./hosts/swagwatch-engine/default.nix
            disko.nixosModules.disko
            impermanence.nixosModules.impermanence
          ];
        };

        thesentry = mkHost {
          modules = [
            ./modules/common/base.nix
            ./hosts/thesentry/default.nix
            disko.nixosModules.disko
          ];
        };
      };
    };
}
