# Grafana MCP

The project configures the official Grafana MCP server for OpenCode, Claude
Code, and Codex. The server exposes only datasource discovery, Prometheus,
Loki, and Grafana navigation tools. Write operations are disabled.

The client configurations are:

- `opencode.jsonc` for OpenCode
- `.mcp.json` for Claude Code
- `.codex/config.toml` for Codex

All three clients start the server through `fnox exec`. The Grafana URL is
stored as non-sensitive client configuration, while the service account token
is stored as age-encrypted ciphertext in `fnox.toml`.

## Initial Setup

Install the pinned project tools:

```bash
mise install --locked
```

Generate an age identity and register its public recipient in `fnox.toml`:

```bash
task fnox:age-key
```

The private identity is written to `~/.config/fnox/age.txt` with mode `600`.
It must not be committed. Only its public recipient is added to `fnox.toml`.

Create a read-only Grafana service account token with permission to query the
Prometheus and Loki datasources. Store it interactively so it does not appear
in shell history:

```bash
fnox set GRAFANA_SERVICE_ACCOUNT_TOKEN --provider age
```

The resulting encrypted value in `fnox.toml` is safe to commit. Restart the
MCP client after changing the token. Claude Code may also ask for approval the
first time it loads the project-scoped `.mcp.json` server.

## Rotate The Identity

The task refuses to overwrite an existing identity. To rotate it explicitly:

```bash
task fnox:age-key -- -f
```

Before replacing the private identity, the task updates the recipient and
re-encrypts existing fnox secrets. If recipient update or re-encryption fails,
it restores `fnox.toml` and leaves the existing identity untouched.

Commit the re-encrypted `fnox.toml` after rotating the identity.

Back up the private identity securely. Losing every configured recipient's
private identity makes the committed ciphertext unrecoverable.

## Add Another Computer

The new computer first generates its own identity without changing
`fnox.toml`:

```bash
mkdir -p ~/.config/fnox
age-keygen -o ~/.config/fnox/age.txt
age-keygen -y ~/.config/fnox/age.txt
```

Send only the printed `age1...` recipient to someone using a computer that can
already decrypt the repository secrets. On that authorized computer:

1. Add the new public recipient to `providers.age.recipients` in `fnox.toml`.
2. Re-encrypt the existing values for the updated recipient set:

   ```bash
   fnox reencrypt --force --provider age
   ```

3. Commit and push the updated `fnox.toml`.
4. Pull the commit on the new computer and restart its MCP client.

Adding a recipient string alone does not grant access to ciphertext that was
encrypted previously. The re-encryption step must run on a computer that still
has an authorized private identity.
