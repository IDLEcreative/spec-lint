# Spec template

Copy this file, fill every angle-bracketed slot, then run:

```sh
./spec-lint.sh my-spec.md
```

A worker starts with none of your context. Everything it needs to build the
right thing has to be in this document, in writing. Anything you leave out, it
will decide for you.

The rule the template exists to enforce: **decisions and contracts belong to
you; only the keystroke-level path belongs to the worker.**

---

## SETUP

Where the work happens and what state the worker starts from.

- **Working copy:** `<path, or the command that creates an isolated one>`
- **Base revision:** `<a pinned commit SHA, not a branch name>`
  Pin the SHA. A branch name resolves again at checkout time, and if anything
  advanced the branch in between, the worker builds on a base you never saw.
- **Dependencies:** `<the exact install command, and when to run it>`
- **Environment:** `<which env files to link or copy, and from where>`
  Never print secrets to the log. Never commit an env file.
- **Out of bounds:** all edits live under the working-copy root above. Nothing
  outside it is yours to change.

## CONTEXT

Three to eight lines. What this task is part of, and nothing else. Not the
session story, not the backlog, not the history of how you got here.

- `<why this work exists, in one line>`
- `<the one upstream fact the worker cannot discover by reading the code>`
- `<the exemplar file to read end to end before writing anything: path + why>`

State exemplars as files to read and mirror, never as a description of a
pattern. "Read `<path>` end to end first, then follow its structure" transfers.
A prose summary of that same file does not.

## CONSTRAINTS

Constraints go before the task list, so they are read before the work starts.

- **Do not touch:** `<paths, files, or subsystems that stay frozen>`
- **Do not change:** `<behaviour that looks like a bug and is deliberate>`
  Name it explicitly. A worker that finds a deliberate hard failure will
  otherwise soften it, in good faith, and hand you a silent one.
- **Non-goals:** `<the adjacent work this task deliberately excludes>`
- **Scope of every check, gate and query:** `<per-user, per-tenant, per-record>`
  Name the scope for each one. Unstated scope is the single most expensive
  omission in this template.
- **Failure ordering for every multi-step write:** `<what has to be true if
  step 2 dies after step 1: one transaction, compensate, or refuse>`
  If you have not decided this, you are not ready to dispatch.
- **Derivatives:** `<thumbnails, mirrors, caches, exports, re-indexes>`
  Whatever rule binds the primary artefact binds these too. List them, or they
  will be built without the rule.
- **Gates this code path passes through:** `<flags, kill switches, pause
  switches, rate limits, quotas, permission checks>` with the file and line of
  a sibling call site for each. A new path inherits nothing implicitly.

## TASK

Numbered. Each item names the file path and the anchor inside it.

1. `<file:line or symbol name>` - `<the change, with the literal text, schema,
   signature or definition written out here>`
2. `<...>`
3. `<...>`

Write the schema. Write the function signature. Write the migration. Write any
string that has to land word for word. A worker without a signature invents one,
and it will be plausible.

Leave the execution path open: the order files get visited, how the refactor is
sequenced, and which intermediate helpers exist are the worker's to choose.
Over-specifying the path degrades the result. Under-specifying the semantics
destroys it.

## VALIDATE

Exact commands, with the result that counts as a pass.

```sh
<command>          # expected: <the literal pass condition>
<command>          # expected: <the literal pass condition>
```

**Falsification probe.** One check designed to expose the work as wrong, not to
confirm that it ran:

> `<e.g. "delete <specific line>; the new test has to fail. If it still passes,
> the test proves nothing: fix it before reporting.">`

A probe finds what a green suite hides. Green means the code ran, which is not
the same as the code being right.

**Decision rules with thresholds.** For every judgment call you can see coming,
write the rule and the number now, so the worker resolves it in flight instead
of guessing or stalling:

> `<e.g. "if more than 5 candidates tie, take the lowest id and say so in the
> report">`

## HANDBACK

- **Commits:** `<stage named files only, subject-line format, trailers>`
- **Concurrency:** if the push is rejected, rebase onto the remote and retry
  once, then stop and report.
- **Hooks:** `<any repository hook the worker will hit, and the sanctioned way
  through it>`. An unmentioned blocking hook stalls the run indefinitely.
- **Sub-workers:** if this environment spawns them, state where their
  completion notices go. A worker waiting on a notice routed elsewhere waits
  forever. Tell it to finish its own spec and end its turn.

## REPORT

At most 250 words, in these fields:

- **CHANGED** - files touched, one line each.
- **VALIDATION** - each command from VALIDATE, with its actual output verdict.
- **PROBE** - what the falsification probe did, and what happened.
- **HANDBACK** - commit or push state.
- **SURPRISES** - anything that deviated from this spec, broke unexpectedly,
  contradicted the context above, or was learned the hard way. "None" is a
  valid answer. This field is mandatory.

Summaries and diff statistics only. No full file contents.

SURPRISES is the field that pays for itself. The worker is the only party that
was at the coalface; it sees the stale assumption, the missing dependency and
the sibling change that landed mid-run. Process every entry after the run:
keep it as a rule, or discard it with a one-line reason.

---

## Before dispatch

- [ ] `./spec-lint.sh <this file>` exits 0.
- [ ] Every schema, signature and literal string is written out, not described.
- [ ] Every exemplar is a file path to read, not a prose summary.
- [ ] Every check and query has its scope named.
- [ ] Every multi-step write has its failure ordering named.
- [ ] Every gate, flag and kill switch on the path is listed with a sibling
      call site.
- [ ] Derivatives and side artefacts are enumerated.
- [ ] VALIDATE has a falsification probe, not only a pass check.
- [ ] REPORT demands SURPRISES.

## After the report comes back

The report is a claim, not evidence. Read the whole diff the way you would read
a contributor's pull request, and run the VALIDATE commands yourself. Budget
roughly a tenth of the effort the worker spent. Two failed repair rounds is the
signal to take the task back rather than send a third.
