#!/usr/bin/env bash
#
# Test suite for spec-lint.sh. No test framework, no dependencies.
# Run: ./test-spec-lint.sh    Exit 0 if every test passes.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
LINT="$HERE/spec-lint.sh"

PASS=0
FAIL=0
FAILED_NAMES=""

WORK=$(mktemp -d "${TMPDIR:-/tmp}/spec-lint-test.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

ok() {
  PASS=$((PASS + 1))
  printf '  ok   %s\n' "$1"
}

no() {
  FAIL=$((FAIL + 1))
  FAILED_NAMES="$FAILED_NAMES
    - $1"
  printf '  FAIL %s\n' "$1"
  [ $# -lt 2 ] || printf '       expected: %s\n' "$2"
  [ $# -lt 3 ] || printf '       actual:   %s\n' "$3"
}

assert_eq() {
  # name, expected, actual
  if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "$2" "$3"; fi
}

assert_contains() {
  # name, needle, haystack
  case "$2" in
    "") no "$1" "a non-empty needle" "empty" ; return ;;
  esac
  case "$3" in
    *"$2"*) ok "$1" ;;
    *)      no "$1" "output containing: $2" "$(printf '%s' "$3" | head -5)" ;;
  esac
}

assert_not_contains() {
  case "$3" in
    *"$2"*) no "$1" "output without: $2" "$(printf '%s' "$3" | head -5)" ;;
    *)      ok "$1" ;;
  esac
}

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

cat > "$WORK/dirty.md" <<'EOF'
# Spec: add the export endpoint

Build the endpoint at /export.
Make the access policy match the house pattern.
Return 409 on a conflicting write.
Fill the remaining columns as needed.
EOF

cat > "$WORK/clean.md" <<'EOF'
# Spec: add the export endpoint

Build the endpoint at /export.
Copy the access policy from db/policies/orders.sql lines 12-28.
Return 409 on a conflicting write.
Set every remaining column to NULL.
EOF

cat > "$WORK/wordish.md" <<'EOF'
The rematch queue and the housekeeping job were standardised.
A mismatch between substandard inputs is unmatched here.
EOF

cat > "$WORK/casing.md" <<'EOF'
Set the timeout APPROPRIATELY.
Make the header Match the sibling route.
EOF

cat > "$WORK/fenced.md" <<'EOF'
Prose says as needed here.

```sh
# a comment saying as needed inside a code block
grep -n 'as needed' file
```

Prose says as needed again.
EOF

: > "$WORK/empty.md"

cat > "$WORK/words.txt" <<'EOF'
# a project word list
widget|Widget is our word. Define which widget.
-secure
EOF

cat > "$WORK/custom.md" <<'EOF'
The widget must be secure.
EOF

printf '%s\n' 'Findings on the shared index must be similar.' > "$WORK/second.md"

# ---------------------------------------------------------------------------
printf '\nspec-lint test suite\n\n'
printf 'basic detection\n'
# ---------------------------------------------------------------------------

out=$("$LINT" "$WORK/dirty.md" 2>&1); rc=$?
assert_eq   "dirty spec exits 1" "1" "$rc"
assert_contains "flags 'match' on line 4"     "dirty.md:4:24: match:"     "$out"
assert_contains "flags 'house' on line 4"     "dirty.md:4:34: house:"     "$out"
assert_contains "flags 'as needed' on line 6" "dirty.md:6:28: as needed:" "$out"
assert_contains "counts 3 decisions"          "3 decisions left for the worker to make" "$out"
assert_contains "explains the smuggle"        "Cite the file and line range to mirror"  "$out"
assert_contains "echoes the source line"      "Make the access policy match the house pattern." "$out"
assert_not_contains "does not flag line 3"    "dirty.md:3:" "$out"
assert_not_contains "'handle' is strict-only" "handle:"     "$out"

out=$("$LINT" "$WORK/clean.md" 2>&1); rc=$?
assert_eq   "clean spec exits 0" "0" "$rc"
assert_contains "clean spec says so" "clean (0 decision-smuggling terms in 6 lines)" "$out"

out=$("$LINT" "$WORK/wordish.md" 2>&1); rc=$?
assert_eq "whole-word only: rematch/housekeeping/standardised do not fire" "0" "$rc"

out=$("$LINT" "$WORK/casing.md" 2>&1); rc=$?
assert_eq       "case-insensitive matching exits 1" "1" "$rc"
assert_contains "flags uppercase APPROPRIATELY"  "casing.md:1:17: appropriately:" "$out"
assert_contains "flags capitalised Match"        "casing.md:2:17: match:"         "$out"

# ---------------------------------------------------------------------------
printf '\ninput handling\n'
# ---------------------------------------------------------------------------

out=$(printf 'Make it match the house pattern.\n' | "$LINT" 2>&1); rc=$?
assert_eq       "stdin exits 1"        "1" "$rc"
assert_contains "stdin is labelled"    "(stdin):1:9: match:" "$out"

out=$(printf 'Return 409 on conflict.\n' | "$LINT" - 2>&1); rc=$?
assert_eq "explicit - reads stdin, clean spec exits 0" "0" "$rc"

out=$("$LINT" "$WORK/empty.md" 2>&1); rc=$?
assert_eq       "empty file exits 0"      "0" "$rc"
assert_contains "empty file is reported"  "clean (empty input)" "$out"

out=$("$LINT" "$WORK/does-not-exist.md" 2>&1); rc=$?
assert_eq       "missing file exits 2"        "2" "$rc"
assert_contains "missing file explains why"   "no such file"  "$out"

out=$("$LINT" "$WORK" 2>&1); rc=$?
assert_eq       "directory argument exits 2"  "2" "$rc"
assert_contains "directory argument explains" "not a regular file" "$out"

out=$("$LINT" --nonsense 2>&1); rc=$?
assert_eq       "unknown option exits 2"      "2" "$rc"
assert_contains "unknown option explains"     "unknown option" "$out"

out=$("$LINT" "$WORK/dirty.md" "$WORK/second.md" 2>&1); rc=$?
assert_eq       "two files exit 1"            "1" "$rc"
assert_contains "second file is scanned"      "second.md:1:38: similar:" "$out"
assert_contains "totals aggregate"            "4 decisions left for the worker to make, across 2 files" "$out"

# ---------------------------------------------------------------------------
printf '\nfenced code blocks\n'
# ---------------------------------------------------------------------------

out=$("$LINT" "$WORK/fenced.md" 2>&1)
assert_contains "prose before the fence is flagged" "fenced.md:1:"  "$out"
assert_contains "prose after the fence is flagged"  "fenced.md:8:"  "$out"
assert_not_contains "fenced code is skipped"        "fenced.md:4:"  "$out"

out=$("$LINT" --include-code "$WORK/fenced.md" 2>&1)
assert_contains "--include-code scans the fence"    "fenced.md:4:"  "$out"

# ---------------------------------------------------------------------------
printf '\nvocabulary control\n'
# ---------------------------------------------------------------------------

out=$("$LINT" --list 2>&1); rc=$?
assert_eq       "--list exits 0"                "0" "$rc"
assert_contains "--list prints a known term"    "match|Match what, exactly?" "$out"
assert_contains "--list prints multi-word term" "as needed|"                 "$out"
assert_not_contains "--list omits strict terms" "gracefully|"                "$out"

count_default=$("$LINT" --list | wc -l | tr -d ' ')
count_strict=$("$LINT" --list --strict | wc -l | tr -d ' ')
if [ "$count_strict" -gt "$count_default" ]; then
  ok "--strict adds terms ($count_default then $count_strict)"
else
  no "--strict adds terms" "more than $count_default" "$count_strict"
fi

out=$(printf 'Handle the edge cases.\n' | "$LINT" 2>&1); rc=$?
assert_eq "'handle' is clean by default" "0" "$rc"
out=$(printf 'Handle the edge cases.\n' | "$LINT" --strict 2>&1); rc=$?
assert_eq "'handle' fires under --strict" "1" "$rc"

out=$("$LINT" -w "$WORK/words.txt" "$WORK/custom.md" 2>&1); rc=$?
assert_eq       "custom word list exits 1"        "1" "$rc"
assert_contains "custom term is flagged"          "custom.md:1:5: widget: Widget is our word." "$out"
assert_not_contains "removed default term is gone" "secure:" "$out"

out=$("$LINT" --words="$WORK/words.txt" --list 2>&1)
assert_contains "--words=FILE form works"  "widget|" "$out"

out=$(SPEC_LINT_WORDS="$WORK/words.txt" "$LINT" "$WORK/custom.md" 2>&1); rc=$?
assert_eq       "SPEC_LINT_WORDS exits 1"      "1" "$rc"
assert_contains "SPEC_LINT_WORDS adds terms"   "widget:" "$out"

out=$("$LINT" -w "$WORK/no-such-words.txt" "$WORK/clean.md" 2>&1); rc=$?
assert_eq       "missing word file exits 2"    "2" "$rc"
assert_contains "missing word file explains"   "word file not found" "$out"

printf 'bareword\n' > "$WORK/bare.txt"
out=$(printf 'A bareword appears here.\n' | "$LINT" -w "$WORK/bare.txt" 2>&1); rc=$?
assert_eq       "term without explanation still fires" "1" "$rc"
assert_contains "term without explanation gets a default reason" \
                "a decision this spec has not written down" "$out"

# auto-pickup of .spec-lint-words from the working directory
mkdir -p "$WORK/proj"
cp "$WORK/custom.md" "$WORK/proj/spec.md"
printf 'widget|Local list works.\n' > "$WORK/proj/.spec-lint-words"
out=$(cd "$WORK/proj" && "$LINT" spec.md 2>&1); rc=$?
assert_eq       ".spec-lint-words is picked up"  "1" "$rc"
assert_contains ".spec-lint-words supplies terms" "Local list works." "$out"

# ---------------------------------------------------------------------------
printf '\noutput control\n'
# ---------------------------------------------------------------------------

out=$("$LINT" --quiet "$WORK/dirty.md" 2>&1); rc=$?
assert_eq "--quiet on a dirty spec exits 1" "1" "$rc"
assert_eq "--quiet prints nothing"          ""  "$out"

out=$("$LINT" -q "$WORK/clean.md" 2>&1); rc=$?
assert_eq "-q on a clean spec exits 0" "0" "$rc"
assert_eq "-q prints nothing"          ""  "$out"

out=$("$LINT" --help 2>&1); rc=$?
assert_eq       "--help exits 0"      "0" "$rc"
assert_contains "--help shows usage"  "Usage:" "$out"

out=$("$LINT" --version 2>&1); rc=$?
assert_eq       "--version exits 0"   "0" "$rc"
assert_contains "--version prints it" "spec-lint.sh 1." "$out"

# ---------------------------------------------------------------------------
printf '\nshipped artefacts\n'
# ---------------------------------------------------------------------------

if [ -f "$HERE/spec-template.md" ]; then
  out=$("$LINT" --strict "$HERE/spec-template.md" 2>&1); rc=$?
  assert_eq "the shipped spec template lints clean under --strict" "0" "$rc"
else
  no "spec-template.md exists" "a file" "missing"
fi

out=$(bash -n "$LINT" 2>&1); rc=$?
assert_eq "spec-lint.sh parses" "0" "$rc"

# ---------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'failed:%s\n' "$FAILED_NAMES"
  exit 1
fi
exit 0
