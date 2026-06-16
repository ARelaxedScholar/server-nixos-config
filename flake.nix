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

    # Weaver has no flake (pure-Python); fetch as a plain source tree and build
    # it in services/weaver.nix.
    weaver = {
      url = "git+ssh://git@gitlab.com/swagwatch/growth/weaver.git";
      flake = false;
    };
  };

  outputs =
    {
      nixpkgs,
      disko,
      impermanence,
      animus,
      llm-agents,
      swagwatch-engine,
      watchtower,
      weaver,
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
          extraSpecialArgs = { inherit animus llm-agents swagwatch-engine watchtower weaver; };
          modules = [
            ./modules/common/base.nix
            ./hosts/swagwatch-engine/default.nix
            disko.nixosModules.disko
            impermanence.nixosModules.impermanence
          ];
        };

        thesentry = mkHost {
          extraSpecialArgs = { inherit llm-agents; };
          modules = [
            ./modules/common/base.nix
            ./hosts/thesentry/default.nix
            disko.nixosModules.disko
          ];
        };
      };
    };
}
