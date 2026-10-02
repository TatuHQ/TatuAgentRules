# Tucano Agent Rules

Single source of truth for organisation-wide AI agent rules shared across
[TucanoTestAPI](https://github.com/TucanoTechnology/TucanoTestAPI),
[TucanoTestGUI](https://github.com/TucanoTechnology/TucanoTestGUI) and
[TucanoTime](https://github.com/TucanoTechnology/TucanoTime).

## How this works

- Rule files live under [`AgentRules/`](AgentRules/) in this repository.
- On every push to `main`, [`sync.yml`](.github/workflows/sync.yml) copies
  `AgentRules/` into each consumer repository listed in that workflow and opens
  a pull request there if the content differs.
- Consumer repositories check `AgentRules/` into their own tree so it is always
  present for a plain clone — nothing needs to be fetched at agent runtime.
- Consumer repositories must **not** edit `AgentRules/` directly. Change it
  here, merge to `main`, and let the sync workflow raise the follow-up PRs.
- [`validate.yml`](.github/workflows/validate.yml) gates every pull request on
  [`scripts/check-rules.sh`](scripts/check-rules.sh), which checks frontmatter,
  file and total size budgets, link targets, routing-table coverage, and
  duplicated prose. Run it locally before committing.

## Adding a consumer repository

1. Add the repository name to the `matrix.repo` list in
   [`.github/workflows/sync.yml`](.github/workflows/sync.yml).
2. Ensure the `SYNC_PAT` secret (see below) has write and pull-request access
   to the new repository.
3. Point that repository's `AGENTS.md` at
   [`AgentRules/README.md`](AgentRules/README.md) — the routing table there maps
   the work in hand to the rule files for it. Do not enumerate the rule files in
   the consumer `AGENTS.md`: a copied list goes stale when a file is renamed,
   and the sync only updates `AgentRules/`.

## Required secret

`SYNC_PAT` — a fine-grained personal access token (or GitHub App installation
token) with `contents: write` and `pull-requests: write` permission on every
consumer repository. The default `GITHUB_TOKEN` cannot push to other
repositories, so this must be created and stored manually as an Actions secret
on this repository. It is never printed or committed.

## Runner requirements

Workflows in this repository run on the organisation's self-hosted runner
(`runs-on: [self-hosted, Linux, X64]`), as every other workflow in the
organisation does — GitHub-hosted runners are billing-gated on this account and
refuse a job before its first step runs. `sync.yml` additionally needs the `gh`
CLI on that runner to open the sync pull requests; when `gh` is missing it stops
with a clear error before touching any consumer repository.

## Repository-specific rules

Rules that only apply to one repository (architecture, storage layout,
language-specific tooling, deployment) stay in that repository's own
`AGENTS.md` and are out of scope for this repository.
