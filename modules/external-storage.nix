{ lib, server, ... }:

let
  cfg = server.storage.externalDisk;

  # The external disk mirrors each relocated dataset under its mount point by
  # basename: /srv/immich-originals -> <mountPoint>/immich-originals.
  bindSource = path: "${cfg.mountPoint}/${baseNameOf path}";

  # nofail keeps a missing/late external disk from blocking boot; the bind
  # mounts additionally wait for (and require) the external mount to be up.
  diskOptions = [
    "nofail"
    "x-systemd.device-timeout=10s"
  ];
  bindOptions = [
    "bind"
    "nofail"
    "x-systemd.requires-mounts-for=${cfg.mountPoint}"
  ];
in
lib.mkIf cfg.enable {
  fileSystems = {
    ${cfg.mountPoint} = {
      device = cfg.device;
      fsType = cfg.fsType;
      options = diskOptions;
    };
  }
  // lib.listToAttrs (
    map (path: {
      name = path;
      value = {
        device = bindSource path;
        # "none" is the conventional fsType for bind mounts. It is also required
        # since 26.05: the zfs module forces every fileSystems.*.fsType to be
        # evaluated, so an unset fsType now aborts evaluation.
        fsType = "none";
        options = bindOptions;
      };
    }) cfg.datasets
  );
}
