# gh-cli-mcp

Wraps the [GitHub CLI](https://cli.github.com/) (`gh`) as MCP tools using
[mcp-cli](https://github.com/pyrex41/mcp-cli), and authenticates `gh` via a
browser using [gh-web-auth](https://github.com/Eun/gh-web-auth) — no PAT or
`gh auth login` device-code copy/paste required.

## What's in the image

- **gh** — official GitHub CLI, installed from GitHub's apt repo.
- **gh-web-auth** — built from source, runs a small web server (default
  `0.0.0.0:8080`) that performs the GitHub OAuth device flow and writes the
  resulting token to `~/.config/gh/hosts.yml` — the exact file/format the
  `gh` CLI itself reads.
- **mcp-cli** — built from source, started with `gh` as the wrapped CLI and
  `mcp-cli-config/gh-config.json` as its tool definitions, so it exposes
  typed MCP tools like `gh_issue_create`, `gh_pr_merge`, `gh_repo_clone`,
  `gh_api`, etc. instead of one raw passthrough tool.
- `entrypoint.sh` starts `gh-web-auth` in the background, then execs
  `mcp-cli` in the foreground so it's PID 1 and receives signals.

## Build

```bash
docker build -t gh-cli-mcp .
```

## Run

```bash
docker run -it --rm -p 8080:8080 gh-cli-mcp
```

Then open `http://localhost:8080` and click **Login with GitHub** to
complete the device-flow auth. Once authenticated, `gh` (and every tool
mcp-cli exposes) can talk to the GitHub API.

To persist the token across container restarts, mount a volume over the gh
config directory:

```bash
docker run -it --rm -p 8080:8080 \
  -v gh-cli-mcp-config:/root/.config/gh \
  gh-cli-mcp
```

## Coverage of the gh CLI config

`mcp-cli-config/gh-config.json` was generated directly from `gh --help` /
`gh <command> <subcommand> --help` output of the actual **gh CLI v2.96.0
binary** (downloaded from `cli/cli`'s GitHub releases and run locally) —
every flag, alias, and positional argument was transcribed from that binary's
own cobra flag registrations, not guessed or reconstructed from memory. It
exposes **137 MCP tools** across 27 command groups:

- `repo`: view, list, clone, create, fork, delete, edit, rename, archive, sync, set-default
- `issue`: list, view, create, edit, close, reopen, comment, delete, pin, unpin, transfer, lock, unlock
- `pr`: list, view, create, edit, close, reopen, merge, checkout, diff, review, comment, ready, lock, unlock, checks
- `release`: list, view, create, edit, delete, download, upload, delete-asset
- `workflow`: list, view, run, enable, disable
- `run`: list, view, watch, cancel, rerun, download, delete
- `gist`: list, view, create, edit, delete, clone, rename
- `label`: list, create, edit, delete, clone
- `auth`: status, login, logout, refresh, token, setup-git, switch
- `search`: repos, issues, prs, code, commits
- `secret` / `variable`: list, set, delete
- `ssh-key` / `gpg-key`: list, add, delete
- `cache`: list, delete
- `ruleset`: list, view, check
- `config`: get, set, list, clear-cache
- `extension`: list, install, upgrade, remove, create, browse
- `project`: list, view, create, delete, field-list, item-list
- `codespace`: list, view, create, delete, ssh, stop, code, edit, ports
- `discussion` (preview): list, view
- `attestation`: verify, download, trusted-root
- `org list`, `browse`, `status`, `alias`: list, set, delete
- `api` (the generic authenticated-request escape hatch)

Not included: purely meta/interactive commands with no scriptable flags of
their own (`gh help`, `gh completion`, `gh preview`) and CLI-preview
features still gated behind separate opt-in (`gh copilot`, `gh skill`,
`gh agent-task`) — add them the same way if you need them, using
`gh <command> --help` as the source of truth.

Notes on the mapping to mcp-cli's schema (`string` / `number` / `boolean`
parameter types only, no native arrays):

- gh flags that accept repeated/comma-separated values (e.g. `--label`,
  `--topic`, `--assignee`) are modeled as a single `string` parameter —
  pass a comma-separated list, exactly as `gh` itself accepts.
- gh commands that take multiple positional arguments (e.g.
  `issue edit <numbers>...`, `gist create <filename>...`) are modeled as one
  `string` positional — pass a space-separated list for the ones that
  support it.
- The `-R/--repo [HOST/]OWNER/REPO` flag inherited by most repo-scoped
  commands is included as a `repo` parameter on every tool that has it.

## Customizing the gh tooling

Edit `mcp-cli-config/gh-config.json` to add/remove `gh` subcommands as MCP
tools — each entry maps a `name`/`subcommand` to typed `parameters` (flags or
positional args), following the format documented in the
[mcp-cli README](https://github.com/pyrex41/mcp-cli#configuration-format).
Rebuild the image after editing.
