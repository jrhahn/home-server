{
  description = "NixOS home server for Seafile, Immich, and family services";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.family-server = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./hosts/family-server
        ];
      };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt;
    };
}
