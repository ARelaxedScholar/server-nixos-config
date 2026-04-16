{
  description = "Multi-host NixOS configuration for swagwatch-engine and thesentry";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko/latest";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    impermanence.url = "github:nix-community/impermanence";
  };

  outputs = { nixpkgs, disko, impermanence, ... }@inputs:
    let
      mkHost = modules:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          inherit modules;
        };
    in {
      nixosConfigurations = {
        swagwatch-engine = mkHost [
          ./modules/common/base.nix
          ./hosts/swagwatch-engine/default.nix
          disko.nixosModules.disko
          impermanence.nixosModules.impermanence
        ];

        thesentry = mkHost [
          ./modules/common/base.nix
          ./hosts/thesentry/default.nix
          disko.nixosModules.disko
        ];
      };
    };
}
