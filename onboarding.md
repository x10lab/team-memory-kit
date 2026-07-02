# Onboarding prompt — AI-context sharing setup

Paste this whole file into Claude Code (or any capable coding agent) **from the root
of the project you want to onboard**. The agent will set the system up end-to-end.

---

## Your task (agent: execute this)

Set up **AI-context sharing** for the current project: share Claude Code memories
(and OMC state, or any declared paths) with teammates via a **separate git repo**,
symlinked into place per-machine, **without ever committing that data to the code
repo**. Then wire it so any teammate adopts it with one command.

Work through the steps below. Ask me the one decision in **Step 3** via a question
with options; infer everything else. At the end, report what's done and the manual
steps that remain (remote creation, committing the scripts).

### Intent & spec (why this exists — honor these invariants)

- **Two locations, one problem.** Claude memories live outside the repo under
  `${CLAUDE_CONFIG_DIR:-~/.claude}/projects/<slug>/`, where `<slug>` is derived from
  the checkout's **absolute path** (so it differs per developer and per worktree).
  OMC state lives in-repo under `.omc/`. Both must be shared *without* landing in the
  code repo's history.
- **Mechanism:** a dedicated git repo (default `~/.ai-context/<project>`) holds the
  shared data; local **symlinks** wire it into the Claude config dir and the repo.
  Symlinks are created locally by a script — **never committed** (they'd bake in one
  person's `$HOME`).
- **Config split:** `ai-context.json` (committed) declares the shared intent —
  project name, context-repo URL, and which paths to share. `.ai-context.local.json`
  (gitignored) holds resolved per-machine paths. Because the URL is committed,
  teammates need **zero env vars**.
- **Distilled, not raw.** Share curated knowledge (memories, plans, specs,
  project-memory). Do **not** share raw `*.jsonl` session transcripts — they're
  machine-specific (path slug), bulky, and don't resume elsewhere.
- **Worktrees:** each linked worktree has a different slug, so `setup` is run once
  per worktree; all worktrees link to the same shared repo.
- **Fragile file links:** a single file a tool rewrites atomically (e.g. OMC's
  `project-memory.json`) can have its symlink replaced by a real file. `setup`/`sync`
  detect this and promote the local content up so nothing is lost. Directory links
  are immune.

### Step 1 — Detect the environment

- `REPO="$(git rev-parse --show-toplevel)"` — confirm we're in a git repo (offer
  `git init` if not).
- Project name = basename of `REPO` (let me override if I say so).
- Package manager: is there a `package.json`? which of pnpm/npm/yarn (lockfile)?
- Does the project use OMC? (is there a `.omc/` dir?) — decides whether to include the
  OMC links.
- Is there existing data to migrate? Look for
  `${CLAUDE_CONFIG_DIR:-~/.claude}/projects/<slug>/memory/` and `.omc/{plans,specs,project-memory.json}`.

### Step 2 — Install the scripts and config

- If `~/.ai-context/_kit/scripts/` exists, copy `ai-context-setup.sh` and
  `ai-context-sync.sh` from there into `./scripts/`. **Otherwise** create them from
  the embedded copies in the appendix below. `chmod +x` both.
- Create `ai-context.json` at the repo root from the template in the appendix. Fill
  `project`. Set `links`: always include the Claude `memory` dir link; include the
  three OMC links **only if** the project uses OMC. Add any other project-specific
  paths worth sharing.
- Wire a runner:
  - If `package.json` exists, add scripts `"ai:setup": "bash scripts/ai-context-setup.sh"`
    and `"ai:sync": "bash scripts/ai-context-sync.sh"`.
  - Otherwise add a `Makefile` with `ai-setup:` / `ai-sync:` targets, or just
    document `bash scripts/ai-context-setup.sh`.
- Update `.gitignore`: ignore `/.ai-context.local.json`; if OMC is used, ignore
  `.omc/` (and `git rm -r --cached .omc` any already-tracked OMC files).

### Step 3 — Ask me: reuse or seed the context repo?

Ask (with options): **"Does a shared context repo already exist for this project?"**
- **Yes, here's the URL** → put it in `ai-context.json` `contextRepo`; `setup` will
  clone it.
- **No, seed a new one** → create `~/.ai-context/<project>/` with subdirs matching the
  `from` paths in `links` (e.g. `claude/memory`, `omc/plans`, `omc/specs`), **migrate
  any existing local data into it** (copy the current `memory/` files and `.omc`
  artifacts), then `git init -b main` + commit. Leave `contextRepo` empty for now and
  tell me to add a remote + push later.

### Step 4 — Run and verify

- Run `bash scripts/ai-context-setup.sh` (or `pnpm ai:setup`).
- Verify: the declared symlinks exist and resolve; `.ai-context.local.json` was
  written and is gitignored; reading a shared file through a symlink works; `git status`
  shows no AI-context **data** staged in the code repo (only `scripts/`, `ai-context.json`,
  `.gitignore`, and the runner change).

### Step 5 — Report

Tell me exactly:
1. What was created/modified in the code repo (to commit).
2. Where the context repo is, and whether it needs a remote + `git push`.
3. The one-command teammate onboarding line (`pnpm ai:setup` or `bash scripts/ai-context-setup.sh`).
4. The reminder to run `setup` once inside each git worktree.

---

## Appendix — embedded files (fallback if `~/.ai-context/_kit` is absent)

### `ai-context.json` (committed; fill `project` and `contextRepo`)

Placeholders in `to`: `$REPO` (repo root), `$CLAUDE_PROJECT`
(`${CLAUDE_CONFIG_DIR:-~/.claude}/projects/<slug>`). `from` is relative to the context repo.

```json
{
  "$schema-note": "Committed, shared config. Teammates need no env vars — setup reads this.",
  "project": "REPLACE_WITH_PROJECT_NAME",
  "contextRepo": "REPLACE_WITH_GIT_URL_OF_CONTEXT_REPO",
  "links": [
    { "type": "dir",  "from": "claude/memory",          "to": "$CLAUDE_PROJECT/memory" },
    { "type": "file", "from": "omc/project-memory.json", "to": "$REPO/.omc/project-memory.json" },
    { "type": "dir",  "from": "omc/plans",               "to": "$REPO/.omc/plans" },
    { "type": "dir",  "from": "omc/specs",               "to": "$REPO/.omc/specs" }
  ]
}
```

### `scripts/ai-context-setup.sh`

```bash
#!/usr/bin/env bash
#
# ai-context-setup.sh — portable AI-context sharing installer / reconciler.
#
# Shares Claude Code memories (and optionally OMC state, or any declared paths)
# across a team via a SEPARATE git repo, symlinked into place per-machine. Never
# commits that data to the code repo.
#
# Config:
#   ai-context.json        (committed)  project + contextRepo + links to share
#   .ai-context.local.json (gitignored) resolved per-machine paths, written here
#
# Works in linked git worktrees: the Claude slug is derived from THIS checkout's
# absolute path, so each worktree links its own slug to the same shared repo.
# Re-run this inside every worktree.
#
# Env overrides:  AI_CONTEXT_REPO  AI_CONTEXT_DIR  AI_CONTEXT_PROJECT  CLAUDE_CONFIG_DIR
set -euo pipefail

REPO="$(git rev-parse --show-toplevel)"
SHARED="$REPO/ai-context.json"
LOCAL="$REPO/.ai-context.local.json"
[ -f "$SHARED" ] || { echo "missing $SHARED — run the onboarding prompt first" >&2; exit 1; }

jget() {  # jget <file> <dotted.key> -> value ("" if absent)
  [ -f "$1" ] || return 0
  node -e 'try{const c=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));let v=c;for(const k of process.argv[2].split("."))v=v?.[k];process.stdout.write(v==null?"":String(v))}catch{}' "$1" "$2"
}

PROJECT="${AI_CONTEXT_PROJECT:-$(jget "$SHARED" project)}"; PROJECT="${PROJECT:-$(basename "$REPO")}"
URL="${AI_CONTEXT_REPO:-$(jget "$SHARED" contextRepo)}"
CLAUDECFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CTX="${AI_CONTEXT_DIR:-$(jget "$LOCAL" contextDir)}"; CTX="${CTX:-$HOME/.ai-context/$PROJECT}"

IS_WT=no
if [ "$(cd "$(git rev-parse --git-dir)" && pwd)" != "$(cd "$(git rev-parse --git-common-dir)" && pwd)" ]; then IS_WT=yes; fi

# 1. clone or fast-forward the shared context repo
if [ -d "$CTX/.git" ]; then
  echo "==> updating context repo at $CTX"
  git -C "$CTX" pull --ff-only 2>/dev/null || echo "   (no upstream to pull; using local state)"
elif [ -n "$URL" ] && [ "$URL" != "REPLACE_WITH_GIT_URL_OF_CONTEXT_REPO" ]; then
  echo "==> cloning $URL -> $CTX"
  git clone "$URL" "$CTX"
else
  echo "no context repo at $CTX and no contextRepo URL set." >&2
  echo "Seed one first (git init \"$CTX\") or set contextRepo in ai-context.json." >&2
  exit 1
fi
[ -z "$URL" ] || [ "$URL" = "REPLACE_WITH_GIT_URL_OF_CONTEXT_REPO" ] && URL="$(git -C "$CTX" remote get-url origin 2>/dev/null || true)"

# 2. resolve slug + placeholders
slug="$(printf '%s' "$REPO" | sed 's/[^a-zA-Z0-9]/-/g')"
CLAUDE_PROJECT="$CLAUDECFG/projects/$slug"
mkdir -p "$CLAUDE_PROJECT"

link_dir() {  local t="$1" l="$2"
  if [ -e "$l" ] && [ ! -L "$l" ]; then echo "   backing up $l -> $l.bak"; rm -rf "$l.bak"; mv "$l" "$l.bak"; fi
  mkdir -p "$(dirname "$l")"; ln -sfn "$t" "$l"; echo "   linked $l -> $t"
}
link_file() {  local t="$1" l="$2"   # promote a rewritten real file up before re-linking
  if [ -f "$l" ] && [ ! -L "$l" ]; then
    if ! cmp -s "$l" "$t"; then echo "   promoting local $l -> shared $t"; cp "$l" "$t"; fi
    rm -f "$l"
  fi
  mkdir -p "$(dirname "$l")"; ln -sfn "$t" "$l"; echo "   linked $l -> $t"
}

# 3. apply declared links (placeholders: $REPO $CLAUDE_PROJECT $CTX)
echo "==> linking shared paths (project=$PROJECT slug=$slug worktree=$IS_WT)"
while IFS=$'\t' read -r type from to; do
  [ -n "$type" ] || continue
  target="$CTX/$from"
  if [ ! -e "$target" ]; then echo "   skip (missing in context repo): $from"; continue; fi
  case "$type" in
    file) link_file "$target" "$to" ;;
    *)    link_dir  "$target" "$to" ;;
  esac
done < <(node -e '
const fs=require("fs");
const c=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
const env={REPO:process.argv[2],CLAUDE_PROJECT:process.argv[3],CTX:process.argv[4]};
const exp=s=>String(s).replace(/\$\{?(\w+)\}?/g,(_,k)=>env[k]??"");
for(const l of (c.links||[])) console.log([l.type||"dir", l.from, exp(l.to)].join("\t"));
' "$SHARED" "$REPO" "$CLAUDE_PROJECT" "$CTX")

# 4. persist resolved local state
node -e '
const fs=require("fs");
const [file,repoRoot,project,contextDir,contextRepoUrl,claudeConfigDir,slug,isWorktree]=process.argv.slice(1);
let p={}; try{p=JSON.parse(fs.readFileSync(file,"utf8"))}catch{}
const now=new Date().toISOString();
fs.writeFileSync(file, JSON.stringify({...p,repoRoot,project,contextDir,contextRepoUrl,claudeConfigDir,slug,isWorktree:isWorktree==="yes",createdAt:p.createdAt||now,updatedAt:now},null,2)+"\n");
' "$LOCAL" "$REPO" "$PROJECT" "$CTX" "$URL" "$CLAUDECFG" "$slug" "$IS_WT"
echo "==> wrote $LOCAL"
echo "==> done."
```

### `scripts/ai-context-sync.sh`

```bash
#!/usr/bin/env bash
#
# ai-context-sync.sh — commit + push local AI-context changes to the shared repo.
# Reconciles any declared file-links a tool may have atomically rewritten (which
# replaces the symlink with a real file) by promoting their content up first.
set -euo pipefail

REPO="$(git rev-parse --show-toplevel)"
SHARED="$REPO/ai-context.json"
LOCAL="$REPO/.ai-context.local.json"

jget() {
  [ -f "$1" ] || return 0
  node -e 'try{const c=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));let v=c;for(const k of process.argv[2].split("."))v=v?.[k];process.stdout.write(v==null?"":String(v))}catch{}' "$1" "$2"
}

PROJECT="$(jget "$SHARED" project)"; PROJECT="${PROJECT:-$(basename "$REPO")}"
CTX="${AI_CONTEXT_DIR:-$(jget "$LOCAL" contextDir)}"; CTX="${CTX:-$HOME/.ai-context/$PROJECT}"
[ -d "$CTX/.git" ] || { echo "no context repo at $CTX — run setup first" >&2; exit 1; }
echo "==> syncing context repo at $CTX"

# reconcile file-links that were replaced by a real file (e.g. atomic rewrites)
CLAUDECFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
slug="$(printf '%s' "$REPO" | sed 's/[^a-zA-Z0-9]/-/g')"
CLAUDE_PROJECT="$CLAUDECFG/projects/$slug"
while IFS=$'\t' read -r from to; do
  [ -n "$from" ] || continue
  target="$CTX/$from"
  if [ -f "$to" ] && [ ! -L "$to" ]; then
    if ! cmp -s "$to" "$target"; then echo "==> promoting rewritten $to"; cp "$to" "$target"; fi
    rm -f "$to"; ln -sfn "$target" "$to"
  fi
done < <(node -e '
const fs=require("fs");
const c=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
const env={REPO:process.argv[2],CLAUDE_PROJECT:process.argv[3],CTX:process.argv[4]};
const exp=s=>String(s).replace(/\$\{?(\w+)\}?/g,(_,k)=>env[k]??"");
for(const l of (c.links||[])) if((l.type||"dir")==="file") console.log([l.from, exp(l.to)].join("\t"));
' "$SHARED" "$REPO" "$CLAUDE_PROJECT" "$CTX")

cd "$CTX"
git pull --ff-only 2>/dev/null || true
if git diff --quiet && git diff --cached --quiet; then echo "==> no context changes to sync"; exit 0; fi
git add -A
git status --short
git commit -m "context: sync $PROJECT memories/state"
if git remote get-url origin >/dev/null 2>&1; then git push; echo "==> pushed to origin"
else echo "==> committed locally (no 'origin' remote set; add one to share)"; fi
```
