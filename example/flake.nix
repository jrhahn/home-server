{
  description = "Private NixOS configuration for my family server";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # Point this at the shareable repo. Pick whichever fits:
    #   url = "github:YOURNAME/home-server";                              # public/shared
    #   url = "git+ssh://git@github.com/YOURNAME/home-server";            # private remote
    #   url = "git+file:///home/you/private/repositories/home-server";    # local checkout
    home-server = {
      url = "github:YOURNAME/home-server";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, home-server, ... }:
    {
      nixosConfigurations.family-server = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          home-server.nixosModules.default
          ./local.nix
          ./hardware-configuration.nix
        ];
      };
    };
}
