# Secrets

Do not commit real secrets.

Create these files on the server:

```bash
sudo install -d -m 0750 -o root -g root /var/lib/secrets
sudo sh -c 'openssl rand -base64 32 > /var/lib/secrets/nextcloud-admin-pass'
sudo chmod 0400 /var/lib/secrets/nextcloud-admin-pass
```

Later, this can move to `sops-nix` or `agenix` if you want encrypted secrets in
git.
