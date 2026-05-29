{ lib, config, ... }:

let
  inherit (lib) mkOption types;
  cfg = config.server;
in
{
  options.server = {
    adminUser = mkOption {
      type = types.str;
      default = "admin";
      description = "Primary administrative (wheel) user.";
    };

    adminSshKeys = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "ssh-ed25519 AAAA... you@example.com" ];
      description = ''
        SSH public keys authorized for the admin user.
        Set this in your private config (see ./example/local.nix).
      '';
    };

    adguardDomain = mkOption {
      type = types.str;
      default = "adguard.home.arpa";
    };
    cloudDomain = mkOption {
      type = types.str;
      default = "cloud.home.arpa";
    };
    gitDomain = mkOption {
      type = types.str;
      default = "git.home.arpa";
    };
    homeAssistantDomain = mkOption {
      type = types.str;
      default = "ha.home.arpa";
    };
    photosDomain = mkOption {
      type = types.str;
      default = "photos.home.arpa";
    };

    enablePublicTls = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable ACME / public HTTPS. Leave off for a private deployment that is
        only reachable over the local network and Tailscale.
      '';
    };

    tailscaleAddress = mkOption {
      type = types.str;
      default = "";
      example = "100.64.0.1";
      description = ''
        Tailscale IP of this server, used for split-horizon DNS answers and
        /etc/hosts entries. Set this in your private config.
      '';
    };

    backups.hetzner = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Send a second Borg copy to a Hetzner Storage Box.";
      };
      user = mkOption {
        type = types.str;
        default = "";
        example = "u123456";
      };
      host = mkOption {
        type = types.str;
        default = "";
        example = "u123456.your-storagebox.de";
      };
      repoPrefix = mkOption {
        type = types.str;
        default = "borg/home-server";
      };
      sshKeyFile = mkOption {
        type = types.str;
        default = "/var/lib/secrets/borg-hetzner-ed25519";
        description = "Path to the Borg SSH key on the server (not in the Nix store).";
      };
      passphraseFile = mkOption {
        type = types.str;
        default = "/var/lib/secrets/borg-hetzner-passphrase";
        description = "Path to the Borg passphrase on the server (not in the Nix store).";
      };
    };

    backups.notify = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Email a summary after each Hetzner backup job (and on failure).";
      };
      onSuccess = mkOption {
        type = types.bool;
        default = true;
        description = "Email on success too. If false, only failures are sent.";
      };
      to = mkOption {
        type = types.str;
        default = "";
        example = "me@example.com";
      };
      from = mkOption {
        type = types.str;
        default = "";
        description = "Sender address. For Gmail this must equal smtpUser.";
      };
      smtpHost = mkOption {
        type = types.str;
        default = "";
        example = "smtp.gmail.com";
      };
      smtpPort = mkOption {
        type = types.port;
        default = 587;
      };
      smtpUser = mkOption {
        type = types.str;
        default = "";
        example = "me@gmail.com";
      };
      passwordFile = mkOption {
        type = types.str;
        default = "/var/lib/secrets/msmtp-password";
        description = "Path to the SMTP password / Gmail App Password (not in the Nix store).";
      };
    };
  };

  config = {
    # Keep the existing `{ server, ... }:` module argument working without
    # rewriting every module to read config.server directly.
    _module.args.server = cfg;

    assertions = [
      {
        assertion = cfg.tailscaleAddress != "";
        message = "server.tailscaleAddress must be set in your private config (see ./example/local.nix).";
      }
      {
        assertion =
          !cfg.backups.hetzner.enable || (cfg.backups.hetzner.user != "" && cfg.backups.hetzner.host != "");
        message = "server.backups.hetzner.enable requires server.backups.hetzner.user and .host to be set.";
      }
      {
        assertion =
          !cfg.backups.notify.enable
          || (
            cfg.backups.notify.to != ""
            && cfg.backups.notify.from != ""
            && cfg.backups.notify.smtpHost != ""
            && cfg.backups.notify.smtpUser != ""
          );
        message = "server.backups.notify.enable requires to, from, smtpHost, and smtpUser to be set.";
      }
    ];
  };
}
