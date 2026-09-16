{
  description = "Reusable NixOS modules for a self-hosted family server (Seafile, Immich, Forgejo, Home Assistant, AdGuard)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # The sensor fleet's own repository, for the module that archives its MQTT
    # readings into QuestDB (server.smarthomeTimeseries). Fetched from GitHub
    # rather than from a checkout on the machine: the repository is public, so
    # this needs no key even when `nixos-rebuild` evaluates as root, and the
    # module belongs to the fleet rather than to this house.
    rs-smarthome-nodes = {
      url = "github:jrhahn/rs-smarthome-nodes/develop";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      rs-smarthome-nodes,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      # Instantiated with allowUnfree because some packages pulled from
      # unstable (e.g. claude-code, codex) have unfree licenses. The NixOS
      # `nixpkgs.config` option does not apply here, since this package set is
      # created outside the NixOS module evaluation.
      pkgsUnstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      # The shareable part. Import this from your own private flake and add a
      # local.nix (your Tailscale IP, SSH keys, Storage Box) plus a
      # hardware-configuration.nix. See ./example for a template.
      nixosModules.default = {
        imports = [
          {
            _module.args.pkgsUnstable = pkgsUnstable;
          }
          ./modules/options.nix
          ./modules/system.nix
          ./modules/adguard-home.nix
          ./modules/base.nix
          ./modules/claude-code.nix
          ./modules/docker.nix
          ./modules/external-storage.nix
          ./modules/forgejo.nix
          ./modules/home-assistant.nix
          ./modules/immich.nix
          ./modules/maintenance.nix
          ./modules/mosquitto.nix
          ./modules/paperless.nix
          ./modules/print-server.nix
          ./modules/reverse-proxy.nix
          ./modules/seafile.nix
          ./modules/smarthome-timeseries.nix
          rs-smarthome-nodes.nixosModules.smarthome-timeseries
          ./modules/storage.nix
          ./modules/trmnl.nix
        ];
      };

      # Reference instance, built from placeholder values in ./example. Useful
      # for `nix flake check` and as the canonical reference for a private flake.
      # Do NOT deploy this directly; deploy your own private flake instead.
      #
      # Deliberately named `example` (not `family-server`): so a stray
      # `nixos-rebuild switch --flake .#family-server` in this repo errors out
      # instead of silently deploying placeholder SSH keys onto the real host.
      # It is also tagged `isReferenceInstance`, which makes activation abort
      # outright (see modules/system.nix) as a second line of defence.
      nixosConfigurations.example = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.default
          ./example/local.nix
          ./example/hardware-configuration.nix
          { server.isReferenceInstance = true; }
        ];
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
