#!/usr/bin/env bash
#
# Add a project to the Boot.dev index.
#
#   ./add-project.sh <repo> [description] [section]
#
#   <repo>         repo name under your GitHub account (e.g. "linko")
#   [description]  one-line blurb for the table; defaults to the repo's
#                  GitHub description
#   [section]      "## <section>" heading to file it under (Go, Python, C,
#                  Docker, ...); defaults to the repo's primary language
#
# Does two things:
#   1. adds the `boot-dev` topic to the repo (merging, not replacing, topics)
#   2. inserts a row in README.md, then commits and pushes
#
set -euo pipefail

cd "$(dirname "$0")"

REPO="${1:?usage: ./add-project.sh <repo> [description] [section]}"
DESC="${2:-}"
SECTION="${3:-}"

OWNER="$(gh api user --jq .login)"
SLUG="$OWNER/$REPO"

# --- resolve repo metadata -------------------------------------------------
if ! META="$(gh repo view "$SLUG" --json description,primaryLanguage,isPrivate 2>/dev/null)"; then
  echo "error: can't see repo $SLUG" >&2
  exit 1
fi
[ -n "$DESC" ]    || DESC="$(jq -r '.description // ""' <<<"$META")"
[ -n "$SECTION" ] || SECTION="$(jq -r '.primaryLanguage.name // ""' <<<"$META")"
PRIVATE="$(jq -r '.isPrivate' <<<"$META")"

[ -n "$DESC" ]    || { echo "error: no description given and repo has none" >&2; exit 1; }
[ -n "$SECTION" ] || { echo "error: no section given and repo has no primary language" >&2; exit 1; }

if ! grep -qxF "## $SECTION" README.md; then
  echo "error: no '## $SECTION' section in README.md. Existing sections:" >&2
  grep '^## ' README.md | sed 's/^/  /' >&2
  exit 1
fi

# --- 1. merge the boot-dev topic ----------------------------------------------
mapfile -t TOPICS < <(gh api "repos/$SLUG/topics" --jq '.names[]' 2>/dev/null || true)
ARGS=()
have_boot_dev=0
for t in "${TOPICS[@]}"; do
  ARGS+=(-f "names[]=$t")
  [ "$t" = "boot-dev" ] && have_boot_dev=1
done
[ "$have_boot_dev" -eq 1 ] || ARGS+=(-f "names[]=boot-dev")
echo "topics: $(gh api -X PUT "repos/$SLUG/topics" "${ARGS[@]}" --jq '.names | join(", ")')"

# --- 2. insert the README row -----------------------------------------------
suffix=""
[ "$PRIVATE" = "true" ] && suffix=" *(private)*"
ROW="| $REPO | $DESC | [$REPO](https://github.com/$SLUG)$suffix |"

if grep -qF "](https://github.com/$SLUG)" README.md; then
  echo "note: $REPO already listed in README.md, skipping row insert"
else
  awk -v sec="## $SECTION" -v row="$ROW" '
    BEGIN { ins=0; inSec=0; sawRow=0 }
    {
      if ($0 == sec)             { inSec=1; print; next }
      if (inSec && !ins) {
        if ($0 ~ /^\| /)         { sawRow=1; print; next }
        if (sawRow && ($0 ~ /^## / || $0 ~ /^[[:space:]]*$/)) {
          print row; ins=1; print; next
        }
      }
      print
    }
    END { if (!ins) print row }
  ' README.md > README.md.tmp && mv README.md.tmp README.md
  echo "readme: added row under '## $SECTION'"
fi

# --- commit + push ---------------------------------------------------------
if git diff --quiet -- README.md; then
  echo "nothing to commit"
else
  git add README.md
  git commit -q -m "Add $REPO"
  git push -q
  echo "pushed."
fi
