{
  config,
  lib,
  server,
  ...
}:

# GitHub Actions self-hosted runners for private repositories, jailed in a
# NixOS container. Jobs run code from the repository *and* from everything a
# build pulls in (crates, pub packages, actions), so the container gets:
#
# - its own root file system: no /home, /srv, /var/lib/secrets or host state;
#   only the registration tokens are bind-mounted, read-only;
# - internet through NAT, but no route to the LAN, the tailnet or the host
#   (dropped below, IPv4 and IPv6);
# - hard cgroup limits, so a build cannot starve Home Assistant or Immich.
#
# See docs/github-runner.md for the token, the first start and the checks.

let
  cfg = server.githubRunner;
  name = "gh-runner";
  # nspawn names the host side of the veth pair "ve-<container>"
  veth = "ve-${name}";
  hostAddress = "10.231.0.1";
  localAddress = "10.231.0.2";
  # everything a job must not reach: LAN, CGNAT/tailnet, link-local, multicast
  blockedV4 = [
    "10.0.0.0/8"
    "172.16.0.0/12"
    "192.168.0.0/16"
    "100.64.0.0/10"
    "169.254.0.0/16"
    "224.0.0.0/4"
  ];
  runnerName = repo: lib.replaceStrings [ "/" ] [ "-" ] repo;
in
lib.mkIf cfg.enable {
  assertions = [
    {
      assertion = cfg.repos != [ ];
      message = "server.githubRunner.enable needs at least one repository in server.githubRunner.repos.";
    }
    {
      # the jail below is written for the iptables firewall backend
      assertion = !config.networking.nftables.enable;
      message = "server.githubRunner expects the iptables firewall (networking.nftables.enable = false).";
    }
  ];

  containers.${name} = {
    autoStart = true;
    privateNetwork = true;
    inherit hostAddress localAddress;
    bindMounts."/run/github-runner-tokens" = {
      hostPath = cfg.tokenDir;
      isReadOnly = true;
    };

    config =
      { pkgs, ... }:
      {
        system.stateVersion = "25.11";

        # Public resolvers: the host's AdGuard is on the LAN, which is closed.
        networking.useHostResolvConf = false;
        networking.nameservers = [
          "9.9.9.9"
          "149.112.112.112"
        ];

        users.users.runner = {
          isSystemUser = true;
          group = "runner";
          home = "/var/lib/runner";
          createHome = true;
        };
        users.groups.runner = { };

        # for the checks in docs/github-runner.md
        environment.systemPackages = [ pkgs.curl ];
        systemd.tmpfiles.rules = [
          "d /var/lib/runner/toolcache 0750 runner runner -"
        ]
        ++ map (repo: "d /var/lib/runner/${runnerName repo} 0750 runner runner -") cfg.repos;

        # Actions download prebuilt Linux binaries (Flutter, Rust toolchains via
        # rustup, cargo tools); nix-ld lets them find a loader and the usual
        # libraries.
        programs.nix-ld = {
          enable = true;
          libraries = with pkgs; [
            stdenv.cc.cc.lib
            zlib
            openssl
            curl
            glib
            libGL
            fontconfig
            freetype
            expat
            xz
            bzip2
            libxml2
            icu
            sqlite
            util-linux
          ];
        };

        services.github-runners = lib.listToAttrs (
          map (repo: {
            name = runnerName repo;
            value = {
              enable = true;
              url = "https://github.com/${repo}";
              tokenFile = "/run/github-runner-tokens/${runnerName repo}";
              # Least privilege: a registration token can only register this
              # runner and expires after an hour; a PAT would need admin
              # rights on the repository. (The module also hides its token
              # copy from the jobs via InaccessiblePaths.)
              tokenType = "registration";
              extraLabels = [ cfg.label ];
              replace = true;
              user = "runner";
              group = "runner";
              # on disk, not in the RAM-backed runtime directory (HOME is the
              # work dir, so caches of Flutter, cargo and pub land here too)
              workDir = "/var/lib/runner/${runnerName repo}";
              extraPackages = with pkgs; [
                bzip2
                curl
                file
                gcc
                gnumake
                jq
                lsof
                pkg-config
                procps
                python3
                rustup
                unzip
                wget
                which
                xz
                yq-go
                zip
              ];
              extraEnvironment = {
                RUNNER_TOOL_CACHE = "/var/lib/runner/toolcache";
                NIX_LD = "/run/current-system/sw/share/nix-ld/lib/ld.so";
                NIX_LD_LIBRARY_PATH = "/run/current-system/sw/share/nix-ld/lib";
              };
              serviceOverrides.ReadWritePaths = [ "/var/lib/runner" ];
            };
          }) cfg.repos
        );
      };
  };

  networking.nat = {
    enable = true;
    internalInterfaces = [ veth ];
    externalInterface = cfg.externalInterface;
  };

  # The jail: nothing from the container to the host, and nothing forwarded
  # to private, tailnet, link-local or multicast addresses. IPv6 gets no
  # route at all; only the link-local address to the host exists, and that
  # is dropped too.
  networking.firewall.extraCommands = ''
    iptables -N gh-runner-jail 2>/dev/null || iptables -F gh-runner-jail
    ${lib.concatMapStrings (net: ''
      iptables -A gh-runner-jail -d ${net} -j DROP
    '') blockedV4}
    iptables -C FORWARD -i ${veth} -j gh-runner-jail 2>/dev/null \
      || iptables -I FORWARD 1 -i ${veth} -j gh-runner-jail
    iptables -C INPUT -i ${veth} -j DROP 2>/dev/null \
      || iptables -I INPUT 1 -i ${veth} -j DROP
    ip6tables -C INPUT -i ${veth} -j DROP 2>/dev/null \
      || ip6tables -I INPUT 1 -i ${veth} -j DROP
    ip6tables -C FORWARD -i ${veth} -j DROP 2>/dev/null \
      || ip6tables -I FORWARD 1 -i ${veth} -j DROP
  '';
  networking.firewall.extraStopCommands = ''
    iptables -D FORWARD -i ${veth} -j gh-runner-jail 2>/dev/null || true
    iptables -D INPUT -i ${veth} -j DROP 2>/dev/null || true
    iptables -F gh-runner-jail 2>/dev/null || true
    iptables -X gh-runner-jail 2>/dev/null || true
    ip6tables -D INPUT -i ${veth} -j DROP 2>/dev/null || true
    ip6tables -D FORWARD -i ${veth} -j DROP 2>/dev/null || true
  '';

  # Builds yield to the family services: hard caps, low CPU and IO weight.
  systemd.services."container@${name}".serviceConfig = {
    MemoryMax = cfg.memoryMax;
    CPUQuota = cfg.cpuQuota;
    CPUWeight = 20;
    IOWeight = 20;
  };

  systemd.tmpfiles.rules = [ "d ${cfg.tokenDir} 0700 root root -" ];
}
