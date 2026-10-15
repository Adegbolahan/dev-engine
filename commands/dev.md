---
description: Run a gated development workflow (feature, bugfix, review, docs, ui-design), or list, init, doctor, drift, resume.
argument-hint: <workflow> <args> | list | init | doctor | drift [--fetch] | resume [run-id]
---

You are running the dev-engine. It is instructions, not code: you read the
engine spec, a profile and a workflow, and you follow them exactly.

Arguments: `$ARGUMENTS`

The plugin root is `${CLAUDE_PLUGIN_ROOT}`. Paths below are relative to it
unless they start with `.dev-engine/` or `.claude/`, which are in the repo
being worked on. Never put a profile, ledger or trust record in the plugin
root, and never edit an installed copy (a plugins cache directory): an update
replaces it. When the repo being worked on is the plugin's own source
checkout, its files are repo files like any other.

The repo's profile is `.claude/dev-engine.yaml` in the repo. The user ledger
is the file named by `DEV_ENGINE_LEDGER`, else
`~/.config/dev-engine/ledger.yaml`. The trust record is
`~/.config/dev-engine/trusted.yaml`. `locations` in `engine/engine.yaml`
gives the schema of all three.

A repo's profile holds shell commands, so it is not run until the person has
trusted it (see "Start a run"). Check with
`ruby ${CLAUDE_PLUGIN_ROOT}/scripts/config.rb trusted <repo>` (exit 0 means
trusted); record with `ruby ${CLAUDE_PLUGIN_ROOT}/scripts/config.rb trust <repo>`.

## Pick the mode from the first argument

- **No argument, or `list`**: read every `workflows/*.yaml` and print a table
  of name, arguments and description. Then read the current repo's
  `.claude/dev-engine.yaml` and name its profile, or say the repo has none
  and that `init` sets one up. Stop.
- **`init`**: follow "Set up a repo" below, then stop.
- **`doctor`**: run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh` and
  `ruby ${CLAUDE_PLUGIN_ROOT}/scripts/validate.rb`, show both outputs as they
  are, and stop. Do not fix anything unless asked.
- **`drift [--fetch]`**: run `ruby ${CLAUDE_PLUGIN_ROOT}/scripts/drift.rb`, passing
  `--fetch` if it was given, and show the output as it is. It compares the
  user ledger, each ledger repo's profile file and the paths cited by the
  plugin's skills and each repo's `.claude/skills/` with the repos on this
  machine. Say plainly that prose rules and versions are not checked. Do not
  fix anything unless asked. Stop.
- **`resume [run-id]`**: follow `run_log.resume` in `engine/engine.yaml`.
  Before walking any step, re-read the profile of the run's repo and of each
  repo in the log's `repos`, and check each one's trust as "Start a run"
  step 2 does: a profile changed since the run started is asked about again.
  Then continue from "Walk the steps".
- **Anything else**: it is a workflow name. The rest of the arguments are the
  workflow's `args`. If no `workflows/<name>.yaml` exists, list the workflows
  and stop.

## Set up a repo

`init` sets up the current repo: its profile file and its entry in the user
ledger. It starts no run, writes nothing else in the repo, and writes
nothing under the plugin root.

1. Confirm you are in a git repo; if not, say so and stop. If the repo is
   the plugin root (`${CLAUDE_PLUGIN_ROOT}`), say that the plugin's own
   profile is maintained by hand in its source, and stop. If the repo already
   has `.claude/dev-engine.yaml`, show it and ask whether to update it or
   keep it.
2. Gather the facts from the repo, not from memory. When a profile exists,
   take **name** and **description** from it; do not derive them again.
   - **name**: the repo's name in kebab-case. If the user ledger already has
     `repo:<name>` with a `path_hint` that is not this repo, ask for another.
   - **description**: what the repo is, in one line.
   - **base_branch**: the remote's default branch, else the current one.
   - **forge**: `github` or `gitlab` from the remote host, else `none`.
   - **commands**: for each key in `engine.yaml` `commands`, find what this
     repo uses by reading its manifest, task runner, CI config, README and
     CLAUDE.md. Prefer what CI runs.
     If the person keeps the existing profile, the facts are what it holds and
     steps 3 and 4 cover only the ledger entry and, if they want it, its commands.
     If an existing profile is not trusted, show its `commands` and `workspace`
     strings exactly as written and ask with AskUserQuestion whether to run
     them. If the person declines, run none of them and mark each "not run".
3. Run each command you found, as written, and keep the result. A key the
   repo has no command for is null. Do not install dependencies, change
   files or fix failures to get a pass. For `run`, start it only if you can
   confirm it came up and stop it cleanly; otherwise leave it for the person
   to confirm.
4. Show the proposed profile (or the existing one, if kept), the ledger path
   and the ledger entry, with each command marked passed, failed (with its
   output) or not run. Ask with AskUserQuestion: approve, revise or abort. A
   failing or unrun command goes in only if the person says to keep it.
5. On approval, write the profile to `.claude/dev-engine.yaml` in the repo,
   as `locations.profile` describes, unless the person kept the existing one.
   Whether the profile was written or kept, add or update the `repo:<name>`
   entry (with `path_hint` set to this clone and `description`) in the user
   ledger; this was shown in step 4 and approved with it. If the ledger does
   not exist, create it and its directory first, with today's date as
   `surveyed` and empty `packages`, `environments` and `edges`. Leave every
   other entry as it is. Add no edges: those are added as they are confirmed
   against source. Do not record trust yet.
6. From the repo, run `ruby ${CLAUDE_PLUGIN_ROOT}/scripts/validate.rb`. If it
   fails, show the output and fix only what this change broke, in the two
   files `init` wrote. If a fix changes the profile, show the change and get
   it approved. Once validate passes, and only if the person approved the
   profile's commands (the profile written, or the kept one shown with its
   commands), record its digest as trusted with the `trust` command above.
7. Report what was written and where, which commands were not confirmed, and
   what is still to do: commit `.claude/dev-engine.yaml` so every clone of
   the repo gets it; write the repo's stack skills in its `.claude/skills/`;
   add ledger edges as they are confirmed against source.

## Start a run

1. Read `engine/engine.yaml` in full. Its `rules`, `statuses`, `failure` and
   `run_log` sections bind this run.
2. Read the current repo's `.claude/dev-engine.yaml`; that is the run's
   profile. If the repo has none, say so, say that `init` sets one up, and
   stop. Then check its trust. If the profile is not trusted (never
   approved, or its file changed since), show its `commands` and `workspace`
   strings exactly as written and ask with AskUserQuestion: trust and
   continue, or abort. Run nothing from the profile before it is trusted. On
   trust, record its digest with the `trust` command above, then continue.
   On abort, stop. Other repos of a run are known only once the plan or bug
   spec lists them under `Repos`; `rules.multi_repo` says when each gets the
   same check.
3. Read `workflows/<name>.yaml`. If the workflow needs `args` and none were
   given, ask for them.
4. Create the run log at `.dev-engine/runs/<run-id>.yaml` as the engine spec
   describes, and make sure `.dev-engine/` is ignored locally.
5. Tell the person in three or four lines what is about to happen: the
   workflow, the profile, the steps in order, and where the gates are.

## Walk the steps

Take the steps in order. For each one:

1. Evaluate `when`. If it is false, log the step as skipped and move on.
2. Log the step as running.
3. If the step is `outward`, check the log shows its `gate` approved in this
   run. If not, stop; do not run it.
4. Load the step's `skills` with the Skill tool, as `dev-engine:<skill>`.
   They must be among the workflow's declared `skills`.
5. Do what the step's type calls for:
   - **instruct**: do what `do` says. With `delegate`, spawn that agent with
     the Agent tool as `dev-engine:<agent>`, using the model the workflow
     declares for it, and give it a prompt that stands alone: the `do` text,
     the repo path, the profile's commands and the paths of the `inputs`.
   - **agents**: spawn every agent in `spawn` in one message so they run in
     parallel, each with the `prompt`, the repo path and the `inputs` paths,
     each on its declared model. When all have reported, merge as `merge`
     says. Never write a report for an agent that has not returned.
   - **check**: run the profile's command for each key in `run`, in order. A
     null command is skipped, and with `defer_to_commit` so is a key the
     profile lists under `commit_hook`. In a run that spans repos, do this in
     each repo with its own profile. Follow `failure.check_with_fix` when `fix` is
     true; otherwise a failing command fails the step.
   - **gate**: show what is being approved, then ask with AskUserQuestion,
     offering approve, revise and abort. Record the answer and any notes in
     the log under `gates.<gate id>` as `answer`, `time` and `notes`, before
     the next step: a hook denies pushes and merge requests until the gate
     that allows them is recorded as approved. Follow `rules.gates`.
   - **artifact**: read `engine/templates/<template>.md`, fill it in from the
     run so far, and write it to `.dev-engine/specs/<run-id>/<template>.md`.
     Keep to `max_lines` and put no code in it. Record the path in the log.
   - **vcs**: follow `rules.workspace` and `rules.multi_repo` first: they say
     where each action happens and in how many repos. `branch` creates and
     switches to a branch off the profile's `base_branch`, named for the
     workflow and the work, or runs the profile's `workspace.create`. `commit` stages only
     the files this run changed and commits with a message that says what
     changed and why. `push` pushes the run's branch and never forces.
     `merge_request` opens one against `base_branch` with the forge's CLI
     (`gh` for github, `glab` for gitlab). `merge` switches to `base_branch`,
     brings it up to date with the remote by fast-forward only (stop if it
     cannot), and merges the run's branch into it with a merge commit; on a
     conflict, abort the merge and stop. `push_base` pushes `base_branch` to
     the remote and never forces. Never commit directly on the base branch:
     it changes only through `merge` and leaves the machine only through
     `push_base`, behind its gate.
   - **workflow**: read `workflows/<run>.yaml` and walk its steps here, inline,
     following `rules.subworkflow`.
   - **loop**: walk the nested steps, then test `until`. Repeat up to `max`
     times. Follow `failure.loop_exhausted`.
6. Log the step's status with a one-line note. On failure, follow the step's
   `on_fail`.

## When the run ends

Set the run's status in the log. Report in a few lines: what was done, where
the artifacts and the log are, what was pushed or opened and where, and
anything left open. Report failures with their output; do not round them up.

## Standing rules

- Do only what the workflow's steps say. If the work needs a step, skill or
  agent the workflow does not declare, stop and say what is missing.
- Never answer a gate yourself, and never treat an earlier approval as
  covering something new.
- The user ledger and the how-to guides in the repo being worked on are
  maps. Confirm against the source before acting on them.
