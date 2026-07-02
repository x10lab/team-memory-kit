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
