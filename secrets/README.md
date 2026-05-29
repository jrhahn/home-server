# Secrets

Do not commit real secrets.

Create these files on the server from the repo root:

```bash
./scripts/create-seafile-secrets.sh
```

Later, this can move to `sops-nix` or `agenix` if you want encrypted secrets in
git.
