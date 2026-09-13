# Secrets

Do not commit real secrets.

Create these files on the server from the repo root:

```bash
./scripts/create-seafile-secrets.sh
```

## Plain password files

A few services read a cleartext password straight from a path under
`/var/lib/secrets`. Create them on the server with a tight umask:

```bash
umask 077
printf '%s' 'your-chosen-password' > /var/lib/secrets/mosquitto-birdscale-password
printf '%s' 'your-chosen-password' > /var/lib/secrets/mosquitto-homeassistant-password
printf '%s' 'your-chosen-password' > /var/lib/secrets/mosquitto-archiver-password
```

| File | Used by |
| --- | --- |
| `mosquitto-birdscale-password` | the sensor fleet's nodes (baked into the firmware's `.env`) |
| `mosquitto-homeassistant-password` | Home Assistant's `mqtt` integration |
| `mosquitto-archiver-password` | the history archiver (`server.smarthomeTimeseries`), read-only |

`mosquitto.nix` hashes them on load; the archiver is handed its copy by systemd
as a credential, so it never appears in the Nix store.

Later, this can move to `sops-nix` or `agenix` if you want encrypted secrets in
git.
