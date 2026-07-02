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
