# CLAUDE.md

Shareable NixOS module set for a family home server. Per-deployment values are
`server.*` options in `modules/options.nix`; the private flake supplies them.
Never commit credentials, IPs, keys, or anything that fingerprints one home —
those belong in the private repo or `/var/lib/secrets`.

## Keep README.md current

README.md is the entry point and must match the code. Any change that touches
one of these updates README.md in the same commit:

- A module added to or removed from `flake.nix` → service list at the top.
- A new or renamed `server.*` option for a service (`enable`, domain) →
  "Services" section, with its default hostname from `modules/options.nix`.
- Paths, exclusions, dumps, or `startAt` times in `modules/maintenance.nix` →
  "Backups" section.
- A new or deleted file under `docs/` → link it from "Getting started" (or
  remove the link).
- Changed setup steps → INSTALLATION.md as well.

Keep the README an overview: one or two lines per feature plus a link to its
guide under `docs/`. Details go in the guide, not the README.

Before finishing, check that every service module in `flake.nix` (not
plumbing like `base.nix`, `system.nix`, `storage.nix`) and every file in
`docs/` is covered in README.md, and that the stated backup times match
`modules/maintenance.nix`.
