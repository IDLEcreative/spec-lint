#!/usr/bin/env bash
#
# spec-lint - flag decision-smuggling words in a delegation spec.
#
# A decision-smuggling word reads like a requirement but is really an unmade
# decision being handed to the worker. "Match the house pattern" is not an
# instruction, it is the author declining to say which pattern. The worker
# will pick one, confidently, and you find out which one later.
#
# Exit codes: 0 clean, 1 findings, 2 usage or I/O error.
#
# Dependencies: bash, awk, tr. All POSIX base. Targets bash 3.2 and later.

set -u
set -o pipefail

VERSION="1.0.0"
PROG=${0##*/}
# ASCII unit separator. Not SOH (\001): bash uses that byte internally in its
# word-splitting machinery, so an IFS of \001 silently refuses to split.
SEP=$'\037'

QUIET=0
STRICT=0
DO_LIST=0
INCLUDE_CODE=0
WORD_FILES=()
FILES=()

# ---------------------------------------------------------------------------
# Vocabulary
#
# One entry per line: term|explanation
# The explanation names the decision being smuggled, so the fix is obvious.
# Terms match whole-word and case-insensitively. Multi-word terms work.
# ---------------------------------------------------------------------------

core_vocabulary() {
  cat <<'EOF'
appropriate|Appropriate by whose measure? Write the exact value, type or rule.
appropriately|The same unmade decision in adverb form. State the rule to apply.
correctly|Correct against which contract? Put the contract in the spec.
properly|You have a standard in mind and have not written it down.
standard|Whose standard? Cite the file that defines it, not the word.
sensible|A sensible default is still a default. Pick it yourself.
reasonable|Reasonable is taste. State the threshold or the value.
match|Match what, exactly? Cite the file and line range to mirror.
matching|Name the artefact being matched and the lines that define it.
matches|Name the artefact being matched and the lines that define it.
house|There is no house style until you name the file that defines it.
as needed|Needed when? State the trigger condition.
if needed|Needed when? State the trigger condition.
if necessary|Necessary when? State the trigger condition.
as appropriate|Two smuggles in one. State the condition and the action.
where appropriate|Enumerate the sites. The worker cannot guess your list.
where relevant|Relevant where? Enumerate the sites.
similar|Similar to what, and alike in which respects?
similarly|Name the thing being echoed and the property being preserved.
etc|The list runs on into items you have not enumerated. Enumerate them.
and so on|The list runs on into items you have not enumerated. Enumerate them.
best practice|Which practice, from which source? Name it or drop it.
best practices|Which practices, from which source? Name them or drop them.
idiomatic|Idiomatic to which codebase? Cite the exemplar file.
consistent|Consistent with which existing artefact? Name it.
consistently|Consistent with which existing artefact? Name it.
existing pattern|Which pattern, in which file? A named pattern can be read.
usual|What is usual to you is unknown to the worker.
normal|Normal is your prior, not a specification.
typical|Typical of what? Give the case you actually want.
obvious|If it were obvious it would be cheap to write down. Write it down.
obviously|If it were obvious it would be cheap to write down. Write it down.
clean|Clean is taste. State the structural requirement instead.
cleanly|Clean is taste. State the structural requirement instead.
robust|Robust against which failures? Enumerate them.
secure|Which threat, which control? Name the posture you want.
securely|Which threat, which control? Name the posture you want.
EOF
}

strict_vocabulary() {
  cat <<'EOF'
handle|Handle how? Every failure path needs a stated outcome.
handles|Handle how? Every failure path needs a stated outcome.
gracefully|Graceful means one specific fallback. Name it.
ensure|Ensure by what mechanism? State the check that proves it.
make sure|Sure by what mechanism? State the check that proves it.
should|Advisory verbs invite negotiation. State the required behaviour.
just|"Just" is usually parked in front of the hard part.
simply|"Simply" is usually parked in front of the hard part.
try to|A worker cannot verify an attempt. State the done condition.
accordingly|Accordingly to what rule? Write the rule.
optimise|Optimise for which metric, to what target?
optimize|Optimise for which metric, to what target?
improve|Improved is measured how? Give the before and the after.
various|Various which? Enumerate them.
several|Several which? Enumerate them.
tbd|An open decision cannot be delegated. Close it or cut the task.
nice to have|Optional scope becomes invented scope. Cut it or require it.
flexible|Flexible along which axis, for which future case?
generic|Generic over what? A generic surface inherits no rules implicitly.
modern|Modern is a moving target. Name the version or the technique.
sane|Sane defaults are your defaults. Write them down.
EOF
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
  cat <<EOF
$PROG $VERSION - flag decision-smuggling words in a delegation spec.

Usage:
  $PROG [options] [file ...]
  cat spec.md | $PROG

Options:
  -s, --strict          Also flag the strict vocabulary (hedges, soft verbs).
  -q, --quiet           Print nothing. Use the exit code.
  -l, --list            Print the active vocabulary and exit.
  -w, --words FILE      Load extra terms from FILE. Repeatable.
      --include-code    Also scan fenced code blocks (skipped by default).
  -h, --help            This text.
  -V, --version         Print the version.

Word files:
  One entry per line, "term|explanation". A term with no explanation gets a
  default one. Lines starting with # are comments. A line starting with -
  removes that term from the defaults, for example "-secure".
  \$SPEC_LINT_WORDS may name an extra word file, and a .spec-lint-words file
  in the working directory is picked up automatically.

Exit codes:
  0  clean
  1  at least one decision-smuggling term found
  2  usage or I/O error
EOF
}

# Lowercases $1 into LOWER_RESULT. Skips the subshell and the tr fork when the
# input is already lowercase, which is every default term.
LOWER_RESULT=""
lower_into() {
  LOWER_RESULT=$1
  case "$LOWER_RESULT" in
    *[A-Z]*) LOWER_RESULT=$(printf '%s' "$LOWER_RESULT" | tr '[:upper:]' '[:lower:]') ;;
  esac
}

die() {
  printf '%s: %s\n' "$PROG" "$1" >&2
  exit 2
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

while [ $# -gt 0 ]; do
  case "$1" in
    -s|--strict)    STRICT=1 ;;
    -q|--quiet)     QUIET=1 ;;
    -l|--list)      DO_LIST=1 ;;
    --include-code) INCLUDE_CODE=1 ;;
    -w|--words)
      [ $# -ge 2 ] || die "--words needs a file argument"
      WORD_FILES[${#WORD_FILES[@]}]="$2"
      shift
      ;;
    --words=*)      WORD_FILES[${#WORD_FILES[@]}]="${1#--words=}" ;;
    -h|--help)      usage; exit 0 ;;
    -V|--version)   printf '%s %s\n' "$PROG" "$VERSION"; exit 0 ;;
    -)              FILES[${#FILES[@]}]="-" ;;
    --)             shift; while [ $# -gt 0 ]; do FILES[${#FILES[@]}]="$1"; shift; done ;;
    -*)             die "unknown option: $1 (try --help)" ;;
    *)              FILES[${#FILES[@]}]="$1" ;;
  esac
  shift
done

# Implicit word files: the env var, then a project-local file.
if [ -n "${SPEC_LINT_WORDS:-}" ]; then
  WORD_FILES[${#WORD_FILES[@]}]="$SPEC_LINT_WORDS"
fi
if [ -f ".spec-lint-words" ]; then
  WORD_FILES[${#WORD_FILES[@]}]=".spec-lint-words"
fi

# ---------------------------------------------------------------------------
# Build the vocabulary
# ---------------------------------------------------------------------------

TERMS=()
REASONS=()

term_index() {
  local needle=$1 i=0
  while [ "$i" -lt "${#TERMS[@]}" ]; do
    if [ "${TERMS[$i]}" = "$needle" ]; then
      printf '%s' "$i"
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

add_term() {
  local term reason idx
  lower_into "$1"
  term=$LOWER_RESULT
  reason=$2
  [ -n "$term" ] || return 0
  if idx=$(term_index "$term"); then
    REASONS[idx]="$reason"
  else
    TERMS[${#TERMS[@]}]="$term"
    REASONS[${#REASONS[@]}]="$reason"
  fi
}

drop_term() {
  local term i keep_t keep_r
  lower_into "$1"
  term=$LOWER_RESULT
  local new_t=() new_r=()
  i=0
  while [ "$i" -lt "${#TERMS[@]}" ]; do
    keep_t=${TERMS[$i]}
    keep_r=${REASONS[$i]}
    if [ "$keep_t" != "$term" ]; then
      new_t[${#new_t[@]}]="$keep_t"
      new_r[${#new_r[@]}]="$keep_r"
    fi
    i=$((i + 1))
  done
  TERMS=(${new_t[@]+"${new_t[@]}"})
  REASONS=(${new_r[@]+"${new_r[@]}"})
}

ingest_vocabulary() {
  local line term reason
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) continue ;;
    esac
    if [ "${line#-}" != "$line" ]; then
      drop_term "${line#-}"
      continue
    fi
    if [ "${line#*|}" != "$line" ]; then
      term=${line%%|*}
      reason=${line#*|}
    else
      term=$line
      reason="Custom term: a decision this spec has not written down."
    fi
    term="${term#"${term%%[![:space:]]*}"}"
    term="${term%"${term##*[![:space:]]}"}"
    reason="${reason#"${reason%%[![:space:]]*}"}"
    add_term "$term" "$reason"
  done
}

# Process substitution, not a pipe: a pipe would build the arrays in a
# subshell and throw them away.
ingest_vocabulary < <(core_vocabulary)
if [ "$STRICT" -eq 1 ]; then
  ingest_vocabulary < <(strict_vocabulary)
fi

for wf in ${WORD_FILES[@]+"${WORD_FILES[@]}"}; do
  [ -e "$wf" ] || die "word file not found: $wf"
  [ -r "$wf" ] || die "word file not readable: $wf"
  ingest_vocabulary < "$wf"
done

if [ "$DO_LIST" -eq 1 ]; then
  i=0
  while [ "$i" -lt "${#TERMS[@]}" ]; do
    printf '%s|%s\n' "${TERMS[$i]}" "${REASONS[$i]}"
    i=$((i + 1))
  done
  exit 0
fi

[ "${#TERMS[@]}" -gt 0 ] || die "vocabulary is empty, nothing to check"

# The scanner reads the vocabulary from a file, so terms never pass through
# any layer that would interpret backslashes or shell metacharacters.
VOCAB_FILE=$(mktemp "${TMPDIR:-/tmp}/spec-lint.XXXXXX") || die "cannot create a temporary file"
trap 'rm -f "$VOCAB_FILE"' EXIT HUP INT TERM

i=0
while [ "$i" -lt "${#TERMS[@]}" ]; do
  printf '%s|%s\n' "${TERMS[$i]}" "${REASONS[$i]}" >> "$VOCAB_FILE"
  i=$((i + 1))
done

# ---------------------------------------------------------------------------
# Scanning
#
# awk does the hot loop (lines x terms literal matching); bash does policy and
# formatting. Records come back separated by SOH so a spec line containing
# tabs, pipes or quotes cannot corrupt the format.
# ---------------------------------------------------------------------------

TOTAL_FINDINGS=0
TOTAL_FILES=0

scan_records() {
  awk -v vocabfile="$VOCAB_FILE" -v include_code="$INCLUDE_CODE" -v sep="$SEP" '
    function isword(c) {
      return (c != "" && c ~ /[A-Za-z0-9_]/)
    }
    BEGIN {
      n = 0
      while ((getline vline < vocabfile) > 0) {
        p = index(vline, "|")
        if (p < 2) continue
        n++
        term[n] = substr(vline, 1, p - 1)
        reason[n] = substr(vline, p + 1)
        tlen[n] = length(term[n])
      }
      close(vocabfile)
      in_fence = 0
      found = 0
    }
    {
      raw = $0
      low = tolower(raw)
      if (!include_code) {
        probe = low
        sub(/^[ \t]+/, "", probe)
        if (probe ~ /^```/ || probe ~ /^~~~/) { in_fence = 1 - in_fence; next }
        if (in_fence) next
      }
      for (i = 1; i <= n; i++) {
        t = term[i]
        tl = tlen[i]
        start = 1
        while (start <= length(low)) {
          p = index(substr(low, start), t)
          if (p == 0) break
          abs = start + p - 1
          before = (abs > 1) ? substr(low, abs - 1, 1) : ""
          after = substr(low, abs + tl, 1)
          if (!isword(before) && !isword(after)) {
            found++
            printf "F%s%d%s%d%s%s%s%s%s%s\n", sep, FNR, sep, abs, sep, t, sep, reason[i], sep, raw
          }
          start = abs + tl
        }
      }
    }
    END {
      printf "S%s%d%s%d\n", sep, NR, sep, found
    }
  '
}

scan_stream() {
  # $1 = display label. The document arrives on stdin.
  local label=$1 findings=0 nlines=0
  local kind f1 f2 f3 f4 f5

  while IFS="$SEP" read -r kind f1 f2 f3 f4 f5; do
    case "$kind" in
      F)
        findings=$((findings + 1))
        if [ "$QUIET" -eq 0 ]; then
          printf '%s:%s:%s: %s: %s\n' "$label" "$f1" "$f2" "$f3" "$f4"
          printf '    %s\n' "$f5"
        fi
        ;;
      S)
        nlines=$f1
        ;;
    esac
  done < <(scan_records)

  TOTAL_FINDINGS=$((TOTAL_FINDINGS + findings))

  if [ "$QUIET" -eq 0 ] && [ "$findings" -eq 0 ]; then
    if [ "$nlines" -eq 0 ]; then
      printf '%s: clean (empty input)\n' "$label"
    else
      printf '%s: clean (0 decision-smuggling terms in %s lines)\n' "$label" "$nlines"
    fi
  fi
}

if [ "${#FILES[@]}" -eq 0 ]; then
  FILES=("-")
fi

for f in "${FILES[@]}"; do
  TOTAL_FILES=$((TOTAL_FILES + 1))
  if [ "$f" = "-" ]; then
    scan_stream "(stdin)"
  else
    [ -e "$f" ] || die "no such file: $f"
    [ -f "$f" ] || die "not a regular file: $f"
    [ -r "$f" ] || die "not readable: $f"
    # shellcheck disable=SC2094  # the file is only ever read; nothing writes to it
    scan_stream "$f" < "$f"
  fi
done

if [ "$QUIET" -eq 0 ] && [ "$TOTAL_FINDINGS" -gt 0 ]; then
  noun="decisions"
  [ "$TOTAL_FINDINGS" -eq 1 ] && noun="decision"
  filenoun="files"
  [ "$TOTAL_FILES" -eq 1 ] && filenoun="file"
  printf '\n%d %s left for the worker to make, across %d %s.\n' \
    "$TOTAL_FINDINGS" "$noun" "$TOTAL_FILES" "$filenoun"
  printf 'Make each one, then write the made decision into the spec.\n'
fi

[ "$TOTAL_FINDINGS" -eq 0 ] || exit 1
exit 0
