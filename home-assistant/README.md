# Home Assistant Config

This directory contains the safe, tracked parts of the Pi Home Assistant config:

- `configuration.yaml`
- `automations.yaml`
- `scripts.yaml`
- `scenes.yaml`
- built-in blueprints

LocalTuya is no longer vendored here. It comes from nixpkgs, declared as a
`customComponents` entry in `modules/home-assistant.nix`; the copy that used to
live under `custom_components/` was rospogrigio/localtuya 5.2.3, whose options
flow raises `AttributeError: property 'config_entry' ... has no setter` on Home
Assistant 2024.11 and later, so no device could be added or edited.

The private state needed for a no-reconfiguration migration is intentionally not
tracked:

- `.storage/`
- `secrets.yaml`
- `zigbee.db`
- logs, caches, SQLite recorder database files

Those private files are kept locally in `.ha-import/homeassistant/`, which is
ignored by git. The import script first installs this tracked config, then
overlays the private Pi import when it is available:

```bash
./scripts/import-home-assistant-config.sh
```

If you want the private files in git too, add encrypted secrets first with
`sops-nix` or `agenix`; do not commit raw Home Assistant storage/auth files.
