{
  description = "Reusable NixOS modules for a self-hosted family server (Seafile, Immich, Forgejo, Home Assistant, AdGuard)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      # The shareable part. Import this from your own private flake and add a
      # local.nix (your Tailscale IP, SSH keys, Storage Box) plus a
      # hardware-configuration.nix. See ./example for a template.
      nixosModules.default = {
        imports = [
          ./modules/options.nix
          ./modules/system.nix
          ./modules/adguard-home.nix
          ./modules/base.nix
          ./modules/docker.nix
          ./modules/external-storage.nix
          ./modules/forgejo.nix
          ./modules/home-assistant.nix
          ./modules/immich.nix
          ./modules/maintenance.nix
          ./modules/reverse-proxy.nix
          ./modules/seafile.nix
          ./modules/storage.nix
        ];
      };

      # Example instance, built from placeholder values in ./example. Useful for
      # `nix flake check` and as the canonical reference for a private flake. Do
      # NOT deploy this directly; deploy your own private flake instead.
      nixosConfigurations.family-server = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.default
          ./example/local.nix
          ./example/hardware-configuration.nix
        ];
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
