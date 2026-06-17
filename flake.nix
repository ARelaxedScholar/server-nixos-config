{
  description = "Multi-host NixOS configuration for swagwatch-engine and thesentry";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko/latest";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    impermanence.url = "github:nix-community/impermanence";
    animus.url = "github:ARelaxedScholar/Animus";
    animus.inputs.nixpkgs.follows = "nixpkgs";
    llm-agents.url =                                                                                                "git+https://github.com/numtide/llm-agents.nix?rev=53673313e86582f3ac7050ff826158fd843c219d";
    swagwatch-engine.url = "git+file:///mnt/data/swagwatch-engine";

    # Watchtower ships its own flake (Rust); use its package output.
    watchtower.url = "git+ssh://git@gitlab.com/swagwatch/observability/watchtower.git";

    # Uriel — 24/7 autonomous agent
    uriel = {
      url = "git+ssh://git@gitlab.com/arelaxedscholar-group/uriel.git";
      flake = true;
    };

    # Weaver has no flake (pure-Python); fetch as a plain source tree and build
    # it in services/weaver.nix.
    weaver = {
      url = "git+ssh://git@gitlab.com/swagwatch/growth/weaver.git";
      flake = false;
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
      packages.${system}.openshell = pkgs.callPackage ./packages/openshell { };

      nixosConfigurations = {
        swagwatch-engine = mkHost {
          extraSpecialArgs = {
            animus = inputs.animus;
            llm-agents = inputs.llm-agents;
            swagwatch-engine = inputs.swagwatch-engine;
            watchtower = inputs.watchtower;
            weaver = inputs.weaver;
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
