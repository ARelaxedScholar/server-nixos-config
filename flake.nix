{
  description = "Multi-host NixOS configuration for swagwatch-engine and thesentry";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko/latest";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    impermanence.url = "github:nix-community/impermanence";
    animus.url = "github:ARelaxedScholar/Animus";
    animus.inputs.nixpkgs.follows = "nixpkgs";
    llm-agents.url = "git+https://github.com/numtide/llm-agents.nix?rev=53673313e86582f3ac7050ff826158fd843c219d";
    swagwatch-engine.url = "git+file:///mnt/data/swagwatch-engine?ref=main";
    swagwatch-engine.inputs.nixpkgs.follows = "nixpkgs";
    swagwatch-social-api.url = "git+file:///mnt/data/swagwatch-social-api?ref=main";
    swagwatch-social-api.inputs.nixpkgs.follows = "nixpkgs";

    # Forge is developed locally on this host for now.
    forge.url = "path:/home/user/workspace/forge";
    forge.inputs.nixpkgs.follows = "nixpkgs";

    # Revision-exact local mirrors keep host rebuilds independent of interactive
    # GitLab SSH credentials. Directory suffixes identify the mirrored commits.
    watchtower.url = "path:/mnt/data/vendor/watchtower-464fb957";
    uriel = {
      url = "path:/mnt/data/vendor/uriel-9e44c3e";
      flake = true;
    };
  };

  outputs =
    { nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      openshell-pkg = pkgs.callPackage ./packages/openshell { };

      mkHost =
        {
          modules,
          extraSpecialArgs ? { },
        }:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs openshell-pkg;
          }
          // extraSpecialArgs;
          inherit modules;
        };
    in
    {
      packages.${system} = {
        openshell = openshell-pkg.openshell-cli;
        openshell-gateway = openshell-pkg.openshell-gateway;
      };

      nixosConfigurations = {
        swagwatch-engine = mkHost {
          extraSpecialArgs = {
            animus = inputs.animus;
            llm-agents = inputs.llm-agents;
            swagwatch-engine = inputs.swagwatch-engine;
            swagwatch-social-api = inputs.swagwatch-social-api;
            forge = inputs.forge;
            watchtower = inputs.watchtower;
            uriel = inputs.uriel;
            inherit openshell-pkg;
          };
          modules = [
            ./modules/common/base.nix
            ./hosts/swagwatch-engine/default.nix
            ./modules/common/openshell.nix
            inputs.disko.nixosModules.disko
            inputs.impermanence.nixosModules.impermanence
          ];
        };

        thesentry = mkHost {
          extraSpecialArgs = { llm-agents = inputs.llm-agents; };
          modules = [
            ./modules/common/base.nix
            ./hosts/thesentry/default.nix
            inputs.disko.nixosModules.disko
          ];
        };
      };
    };
}
