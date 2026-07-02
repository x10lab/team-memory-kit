# AI-Context Sharing Kit

Share Claude Code memories — and optionally [OMC](https://github.com/yeachan-heo/oh-my-claudecode) 
state or any declared paths — across a team through a **separate git repo**, symlinked 
into place per-machine, **without ever committing that data to the code repo**.

Teammates adopt it with **one command**.

## The problem

AI-context lives in two awkward places:

- **Claude memories** live *outside* the repo, under
  `${CLAUDE_CONFIG_DIR:-~/.claude}/projects/<slug>/`, where `<slug>` is derived from
  the checkout's **absolute path** — so it differs per developer and per worktree.
- **OMC state** lives *in-repo* under `.omc/`.

Both hold knowledge worth sharing, and both must be shared *without* landing in the
code repo's history.

## How it works

A dedicated git repo (default `~/.ai-context/<project>`) holds the shared data. A
setup script creates local **symlinks** wiring it into the Claude config dir and the
repo. The symlinks are created locally and **never committed** — committing them would
bake in one person's `$HOME`.

- **`ai-context.json`** (committed) declares the shared intent — project name,
  context-repo URL, and which paths to share. Because the URL is committed, teammates
  need **zero env vars**.
- **`.ai-context.local.json`** (gitignored) holds the resolved per-machine paths.
- Only **distilled** knowledge is shared (memories, plans, specs, project-memory).
  Raw `*.jsonl` session transcripts are **not** shared — they're machine-specific,
  bulky, and don't resume elsewhere.

## Repo layout

```
_kit/
├── ai-context.json          # committed config template (project + contextRepo + links)
├── onboarding.md            # paste-into-Claude prompt that sets a project up end-to-end
├── scripts/
│   ├── ai-context-setup.sh  # installer / reconciler — clones shared repo, creates symlinks
│   └── ai-context-sync.sh   # commit + push local context changes to the shared repo
├── .gitignore
├── LICENSE
└── README.md
```

## Usage

### Onboard a new project

From the root of the project you want to onboard, paste [`onboarding.md`](./onboarding.md)
into Claude Code (or any capable coding agent). It detects the environment, installs the
scripts and `ai-context.json`, wires the `.gitignore`, and either reuses an existing
context repo or seeds a new one — migrating any existing local data.

### Teammate adoption (one command)

Once a project is onboarded and the scripts are committed, a teammate runs:

```bash
bash scripts/ai-context-setup.sh
# or, if wired into package.json:
pnpm ai:setup
```

This clones (or fast-forwards) the shared context repo and creates the symlinks for
this machine.

### Sync your changes back

After Claude accumulates new memories or OMC state:

```bash
bash scripts/ai-context-sync.sh   # or: pnpm ai:sync
```

This commits and pushes the shared repo, promoting any file-links a tool may have
atomically rewritten (which replaces a symlink with a real file) back into the shared
repo first so nothing is lost.

## Worktrees

Each linked git worktree has a different Claude slug, so **run `setup` once inside each
worktree**. All worktrees link to the same shared context repo.

## Configuration reference

`ai-context.json` `links[]` entries. `from` is relative to the context repo; `to`
supports the placeholders `$REPO` (repo root) and `$CLAUDE_PROJECT`
(`${CLAUDE_CONFIG_DIR:-~/.claude}/projects/<slug>`).

| Field  | Values          | Notes                                                        |
| ------ | --------------- | ------------------------------------------------------------ |
| `type` | `dir` \| `file` | Directory links are immune to atomic-rewrite clobbering.     |
| `from` | path            | Location inside the shared context repo.                     |
| `to`   | path            | Where to symlink it locally (placeholders expanded).         |

Env overrides: `AI_CONTEXT_REPO`, `AI_CONTEXT_DIR`, `AI_CONTEXT_PROJECT`,
`CLAUDE_CONFIG_DIR`.

## License

[MIT](./LICENSE) © 2026 x10lab
