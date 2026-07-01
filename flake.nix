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
    swagwatch-engine.url = "git+file:///mnt/data/swagwatch-engine";

    # Forge is developed locally on this host for now. Use a path input so the
    # declarative service can build the current workspace while the repo is being
    # bootstrapped; switch this to the canonical remote once Forge is published.
    forge.url = "path:/home/user/workspace/forge";
    forge.inputs.nixpkgs.follows = "nixpkgs";

    # Weaver is disabled because its GitLab SSH remote cannot be fetched
    # during nix build (no SSH agent in sandbox).
    # Re-enable once GitLab deploy tokens or HTTPS auth is configured.
    watchtower.url = "git+ssh://git@gitlab.com/swagwatch/observability/watchtower.git";
    uriel = {
      url = "git+ssh://git@gitlab.com/arelaxedscholar-group/uriel.git";
      flake = true;
    };
    # weaver = {
    #   url = "git+ssh://git@gitlab.com/swagwatch/growth/weaver.git";
    #   flake = false;
    # };
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
            forge = inputs.forge;
            watchtower = inputs.watchtower;
            # weaver = inputs.weaver;
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
          extraSpecialArgs = {
            llm-agents = inputs.llm-agents;
          };
          modules = [
            ./modules/common/base.nix
            ./hosts/thesentry/default.nix
            inputs.disko.nixosModules.disko
          ];
        };
      };
    };
}
