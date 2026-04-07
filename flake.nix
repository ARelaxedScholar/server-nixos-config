{
  description = "Headless ZFS Impermanence Server";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    disko.url = "github:nix-community/disko/latest";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    impermanence.url = "github:nix-community/impermanence";
    animus.url = "github:ARelaxedScholar/Animus";
    animus.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs =
    {
      self,
      nixpkgs,
      disko,
      impermanence,
      animus,
      ...
    }@inputs:
    {
      nixosConfigurations.server = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs animus; };
        modules = [
          ./configuration.nix
          disko.nixosModules.disko
          impermanence.nixosModules.impermanence
        ];
      };
    };
}
