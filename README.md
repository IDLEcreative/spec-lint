# spec-lint

**A linter for the specs you hand to a coding agent. It flags the words that look like
requirements but are really decisions you have not made.**

When you delegate a task to a worker agent, every vague word in the spec is a decision
you have quietly handed to the worker. "Match the house pattern" is not an instruction.
It is you declining to say which pattern. The worker will pick one, confidently, and you
find out which one when you read the diff, or later, in production.

`spec-lint` reads a spec and flags every one of those words, with the line, the term, and
a one-line note naming the decision being smuggled.

```
$ spec-lint spec.md
spec.md:4:24: match: Match what, exactly? Cite the file and line range to mirror.
    Make the access policy match the house pattern.
spec.md:4:34: house: There is no house style until you name the file that defines it.
    Make the access policy match the house pattern.
spec.md:6:28: as needed: Needed when? State the trigger condition.
    Fill the remaining columns as needed.

3 decisions left for the worker to make, across 1 file.
Make each one, then write the made decision into the spec.
```

Exit code 1 if it finds anything, 0 if the spec is clean. Drop it in a pre-dispatch
check and a spec does not go to the worker until the decisions are made.

## Why this exists

Delegating implementation to a cheaper worker agent works well when the spec is precise
and fails in expensive, subtle ways when it is not. The failures are not random. They
cluster on a small set of words that feel like specification but carry no decision:
*appropriate*, *correctly*, *properly*, *match*, *house*, *sensible*, *as needed*, and
their relatives. Each one reads as a requirement and delegates a judgement.

A few real cases, anonymised:

- A spec saying "match the house pattern" for an access policy produced the wrong
  security posture, because there was no single house pattern and the worker chose one.
- An unstated ordering in a two-step scoring rule ("add a bonus to the lookup") let the
  worker apply the bonus before the relevance gate, so a query that should have matched
  nothing returned whatever the bonus favoured.
- "Handle failures gracefully" produced one fallback where three different failures each
  needed a different response.

None of these were worker mistakes in the ordinary sense. In each case the worker did
exactly what the spec said. The spec had not said enough, and the gap was invisible
because the words sounded specific.

The fix is a discipline: **decide, then delegate.** Before a spec goes out, make every
decision it implies and write the made decision down. `spec-lint` is that discipline made
mechanical, so it does not depend on remembering.

## Install

It is one bash script with no dependencies beyond bash, awk and tr.

```bash
git clone https://github.com/<you>/spec-lint.git
install spec-lint/spec-lint.sh /usr/local/bin/spec-lint   # or just run it in place
```

## Use

```bash
spec-lint spec.md                 # lint a file
cat spec.md | spec-lint           # or a stream
spec-lint --strict spec.md        # also flag hedges and soft verbs
spec-lint --list                  # print the active vocabulary
spec-lint --quiet spec.md; echo $?   # exit code only, for a gate
```

### As a pre-dispatch gate

The intended use is to block a spec from reaching the worker until it lints clean:

```bash
if ! spec-lint --quiet "$SPEC"; then
  echo "Spec has undecided points. Run 'spec-lint $SPEC' and resolve them first." >&2
  exit 1
fi
dispatch-to-worker "$SPEC"
```

### Extending the vocabulary

The default list is opinionated but not fixed. Add your own terms, or remove ones that
do not fit your domain, with a word file:

```
# my-words.txt: one "term|explanation" per line
bespoke|Bespoke to which spec? Point at the definition.
-secure          # drop a default term with a leading dash
```

```bash
spec-lint --words my-words.txt spec.md
```

A `.spec-lint-words` file in the working directory, or a file named by
`$SPEC_LINT_WORDS`, is picked up automatically. Custom terms are the point: the words
that smuggle decisions in your domain are not the same as the defaults.

## What it does not do

- **It does not read your code, only your spec.** It cannot tell whether the spec is
  correct, only whether it is decided.
- **It is not a grammar or style checker.** It flags one specific failure: a word that
  delegates a judgement. A clean lint is not a good spec, only a decided one.
- **It will over-flag, by design.** "Match" is sometimes exactly the right word. The tool
  errs towards flagging, because a false flag costs you a moment and a missed one costs
  you a wrong diff. Remove terms that do not fit your work with a word file.
- **It knows nothing about which model or worker you use.** It lints text.

## Field notes

Vague specs are one class of delegation failure. The other class is the mechanics of the
worker itself: prompts that silently hang, backgrounded runs killed by a timeout, tests
that pass while testing nothing, patches that report success and roll back. Those are
written up in [docs/FIELD-NOTES.md](docs/FIELD-NOTES.md). They are the scars, not the
theory.

## Prior art and credit

This tool is small and specific. The larger idea it sits inside, an expensive model
planning and reviewing while a cheaper worker implements, is not mine and is not new:

- **[Aider](https://aider.chat)'s architect/editor mode** splits the reasoning model
  from the editing model directly.
- **[Cline](https://github.com/cline/cline) and [Roo Code](https://github.com/RooCodeInc/Roo-Code)**
  separate an Architect mode from a Code mode.
- **FrugalGPT** (Stanford) and **RouteLLM** (LMSYS) are the research on cost-tiered
  model routing.

The workflow these notes come from was **adapted from
[steipete](https://github.com/steipete)'s `codex-first` skill**. The contribution here is
the linter and the field notes, not the pattern.

## Licence

MIT. See [LICENSE](LICENSE).
