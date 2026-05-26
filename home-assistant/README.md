# Home Assistant Config

This directory contains the safe, tracked parts of the Pi Home Assistant config:

- `configuration.yaml`
- `automations.yaml`
- `scripts.yaml`
- `scenes.yaml`
- built-in blueprints
- `custom_components/localtuya`

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
