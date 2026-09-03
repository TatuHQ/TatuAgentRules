# Tucano Agent Rules

Single source of truth for organisation-wide AI agent rules shared across
[TucanoTestAPI](https://github.com/TucanoTechnology/TucanoTestAPI) and
[TucanoTestGUI](https://github.com/TucanoTechnology/TucanoTestGUI).

## How this works

- Rule files live under [`AgentRules/`](AgentRules/) in this repository.
- On every push to `main`, [`sync.yml`](.github/workflows/sync.yml) copies
  `AgentRules/` into each consumer repository listed in that workflow and opens
  a pull request there if the content differs.
- Consumer repositories check `AgentRules/` into their own tree so it is always
  present for a plain clone — nothing needs to be fetched at agent runtime.
- Consumer repositories must **not** edit `AgentRules/` directly. Change it
  here, merge to `main`, and let the sync workflow raise the follow-up PRs.

## Adding a consumer repository

1. Add the repository name to the `matrix.repo` list in
   [`.github/workflows/sync.yml`](.github/workflows/sync.yml).
2. Ensure the `SYNC_PAT` secret (see below) has write and pull-request access
   to the new repository.
3. Reference `AgentRules/` from that repository's own `AGENTS.md`.

## Required secret

`SYNC_PAT` — a fine-grained personal access token (or GitHub App installation
token) with `contents: write` and `pull-requests: write` permission on every
consumer repository. The default `GITHUB_TOKEN` cannot push to other
repositories, so this must be created and stored manually as an Actions secret
on this repository. It is never printed or committed.

## Repository-specific rules

Rules that only apply to one repository (architecture, storage layout,
language-specific tooling, deployment) stay in that repository's own
`AGENTS.md` and are out of scope for this repository.
