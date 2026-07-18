# Field notes: driving a CLI coding agent as a worker

These are the things that cost time and were not written down anywhere. Each one
was observed in real use, driving a command-line coding agent (the Codex CLI, but
most of this generalises to any headless worker agent) from an orchestrating
session. The symptom, the cause, and the fix.

The tooling in this repo, `spec-lint`, addresses one class of failure: vague specs.
These notes cover the other class: the mechanics of the worker itself.

## The pattern, honestly

The shape is "an expensive model writes the spec and reviews the result, a cheaper
worker does the typing." That shape is not new. Aider's architect/editor mode, Cline
and Roo Code's Architect and Code separation, and the routing literature (FrugalGPT,
RouteLLM) are all versions of it. This repo does not claim the pattern. It ships the
tooling and the scar tissue.

The one observation worth stating, because most routing writing misses it: the routing
literature assumes per-token API pricing, where sending work to a cheaper model of the
same vendor saves money. On a flat-rate subscription that is false. A cheaper model
from the same vendor draws the same quota, so tier-routing within one vendor saves
nothing. The only lever that moves cost is crossing a billing boundary to a separate
flat-rate plan. Route by billing boundary, not by model capability. It is an
observation, not a law, and it only applies while you are on subscriptions rather than
metered APIs.

## Write the spec against role, not model name

Never write a model's name into a spec, a config, or a workflow file. Say "the
orchestrating model" and "the worker", never the current product names. Models get
renamed and retired on a schedule you do not control. A pipeline written against role
terms survives a model change with zero edits; one written against `some-model-v5`
breaks silently the day that id is deprecated, and the breakage looks like a logic bug,
not a rename. This is cheap insurance and it has paid out.

## The worker hangs forever on an inline-quoted prompt

**Symptom.** You launch the worker with the spec passed as an inline command-line
argument. The process is alive. It produces zero bytes of output. It never finishes.

**Cause.** A long prompt with apostrophes or quotes inside it can be mangled by the
shell or harness eval wrapping before it reaches the worker. The worker then receives
no prompt at all and waits on standard input forever.

**The instant diagnostic.** A healthy run leaves a trace within about a minute: a new
session or rollout file appears in the worker's session directory, naming your working
directory. If the process is alive, output is empty, and no such file exists, it is
hung, not thinking. That check settles hang-versus-thinking immediately, so you never
diagnose by waiting.

**Fix.** Do not pass a long prompt as an inline argument. Redirect it from a file
(`worker < spec.md` or the worker's equivalent), or read it into a single argument with
`"$(cat spec.md)"`. Both avoid the quoting layer entirely.

## An explicit timeout kills a backgrounded run mid-build

**Symptom.** You launch the worker in the background with a generous timeout, expecting
the background flag to let it run long. It dies at exactly the timeout, mid-build.

**Cause.** The harness enforces the timeout even on a backgrounded process. The
background flag does not exempt it.

**Fix.** Omit the explicit timeout on a background launch and let the process run to its
own completion. Recovery when one is killed: the partial output usually survives on
disk, so relaunch the same spec with an "inventory what already exists, keep or fix it,
then complete the rest" preamble rather than starting clean.

## "Resume last session" resolves to the wrong session

**Symptom.** You resume the worker's most recent session to continue a task. It dies
instantly with empty output, or picks up a conversation that is not yours.

**Cause.** A "resume last" flag resolves to the most recent session on the whole
machine, not the most recent in your working directory. If a sibling session is running
the same worker, "last" is theirs, possibly still live.

**Fix.** Capture the session id the worker prints at startup and resume that id
explicitly. If you cannot, start a fresh run with an inventory preamble rather than
gambling on "last".

## Worker-authored tests pass vacuously under a global mock

**Symptom.** The worker writes tests, reports "all passing", and the diff looks
plausible. The tests prove nothing.

**Cause.** The repository's global test setup already mocks a module. The worker adds
its own in-file mock of the same module, which the global setup silently pre-empts, so
the worker's mock function is never wired to anything. Its assertions that the function
was "not called" pass against a function nothing could ever call. A suite made entirely
of negative, not-called assertions can be green while testing nothing.

**Fix.** For any worker-authored test in a repository with a global test setup, require
at least one positive assertion that actually exercises the mocked path. Negative
assertions alone are not evidence. Where the setup file exposes documented hooks for
controlling its mocks, require the worker to use those rather than a fresh in-file mock.

## A three-way patch apply is atomic, and "cleanly" is not "applied"

**Symptom.** You apply a patch and watch it print "applied cleanly" for file after
file. One later file fails. You assume the earlier files landed.

**Cause.** A three-way apply is atomic. A single failing hunk rolls back every file in
the patch, including the ones that already printed "cleanly". Those lines are progress,
not success.

**Fix.** After any patch apply, verify with the repository's status that the hunks
actually landed. When a patch only half-fits, copy whole files from the worker's
checkout once the bases match, rather than trusting a partial apply.

## Restoring a probed file destroys the worker's uncommitted work

**Symptom.** You run a falsification probe on a file (mutate it, confirm a test fails,
then restore it). The restore wipes work the worker had not committed.

**Cause.** Restoring a file to its last committed state (`git checkout <file>` and
similar) reverts to the last commit, not to the pre-probe state. If the worker's change
was still uncommitted, the restore takes it out along with the probe.

**Fix.** Commit the worker's output to a checkpoint before running any mutation probe.
Then a restore returns to the checkpoint, not to the void. This is the same discipline
as committing agent output immediately; a probe is the sneaky path around it.

## A symlinked dependency directory breaks the bundler

**Symptom.** Typecheck, lint and unit tests pass in a worktree, but the production
build fails with an internal bundler error about an invalid symlink.

**Cause.** Symlinking the dependency directory from a main checkout into a worktree is
fine for tools that only read it. Some bundlers reject a dependency symlink that points
outside the project root.

**Fix.** Any worktree that will run a production build needs a real dependency install,
not a symlink. Swap the symlink out first. Related: a backgrounded build can report a
zero exit code even when it failed, so read the log tail for the pass or fail line
rather than trusting the exit code alone.

## Any two-step numeric rule needs its step order written down

**Symptom.** You ask for a scoring or ranking change ("add a same-page bonus to the
lookup"). The worker applies it at the wrong point in the pipeline. A query that should
have matched nothing now "finds" whatever the bonus favoured.

**Cause.** You said what to add but not where, relative to the threshold that gates
results. The worker chose, and chose the point that inverts the intent.

**Fix.** Any rule with two numeric steps needs its order stated: base score, then
threshold gate, then the bonus re-ranks only the qualifiers. This is the same failure
as unstated failure-path ordering. If a rule has steps, write the steps.

## Certify across changes, not just within them

**Symptom.** Several individually-reviewed, individually-green changes to one subsystem
land the same day. Each was correct alone. Together they are broken.

**Cause.** Per-change review cannot see what change A assumed that change B invalidated.
The break lives at the seam, invisible to any single review.

**Fix.** After a multi-change day on one subsystem, run one read-only certification pass
over the current mainline: trace the full path end to end across all the day's changes,
verify each hop's contract, and hunt for cross-change drift. It finds seam breaks that
no per-change review can, and it is one worker run. The orchestrator judges the
findings; "reject with proof" is a valid verdict.

---

The through-line: the worker is fast and confident, and confident is not correct. Every
one of these is a place where the worker's own report ("done", "passing", "applied
cleanly") was true in letter and false in effect. Verify against the artefact, not the
report.
