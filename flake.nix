{
  description = "Multi-host NixOS configuration for swagwatch-engine and thesentry";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko/latest";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    impermanence.url = "github:nix-community/impermanence";
    animus.url = "github:ARelaxedScholar/Animus";
    animus.inputs.nixpkgs.follows = "nixpkgs";
    hermes-agent.url =                                                                              "git+https://github.com/NousResearch/hermes-agent?rev=2483200963e43e7335e02f3f51440db089bcc1a3";
    swagwatch-engine.url = "git+file:///mnt/data/swagwatch-engine";
  };

  outputs =
    {
      nixpkgs,
      disko,
      impermanence,
      animus,
      hermes-agent,
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
          extraSpecialArgs = { inherit animus hermes-agent swagwatch-engine; };
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
