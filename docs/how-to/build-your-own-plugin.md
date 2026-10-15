---
sources:
  - commands/dev.md
  - engine/engine.yaml
  - engine/profiles.yaml
  - engine/templates/story.md
  - engine/templates/plan.md
  - engine/templates/bug.md
  - scripts/validate.rb
  - scripts/guard-agents.sh
  - scripts/session-start.sh
  - scripts/doctor.sh
  - scripts/stack.sh
  - hooks/hooks.json
  - workflows/feature.yaml
  - workflows/bugfix.yaml
  - workflows/review.yaml
  - workflows/docs.yaml
  - ledger/ledger.yaml
---

# Build a dev-engine plugin for your stack

Reuse this plugin's mechanics to give Claude Code gated, repeatable workflows
for any set of repos. This page is for a team starting their own plugin; it
uses this repo as the worked example.

## The idea

One slash command runs a workflow written in YAML. The workflow declares what
Claude does, in what order, with which knowledge, agents and models, and where
a person must approve. The engine is instructions, not code: Claude reads the
YAML and follows it.

## What to copy, and what to write

| Layer         | Files here                                                     | What it does                                                                                              | For your stack                                                                           |
| ------------- | -------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| Command       | `commands/dev.md`                                              | Reads the engine, a profile and a workflow, then walks the steps. Also `list`, `init`, `doctor`, `resume`.        | Copy                                                                                     |
| Engine spec   | `engine/engine.yaml`                                           | Eight step types and the rules every run obeys.                                                           | Copy                                                                                     |
| Templates     | `engine/templates/`                                            | Story, plan and bug spec formats.                                                                         | Copy                                                                                     |
| Validator     | `scripts/validate.rb`                                          | Checks schema, references, hook tests and docs as one system.                                             | Copy                                                                                     |
| Hooks         | `hooks/`, `scripts/guard-agents.*`, `scripts/session-start.sh` | Keeps reviewer agents read-only; adds a start-of-session note in known repos.                             | Copy, with your agent names                                                              |
| Profiles      | `engine/profiles.yaml`                                         | Per repo: how to recognise it and its typecheck, lint, test, build and local-run commands.                | Write                                                                                    |
| Workflows     | `workflows/*.yaml`                                             | Ordered checklists of steps.                                                                              | Copy `feature`, `bugfix`, `review`, `docs`; write the rest                               |
| Skills        | `skills/`                                                      | The knowledge a step or agent loads.                                                                      | Write the stack ones; copy `effective-documentation`, `mr-description`, `repo-claude-md` |
| Agents        | `agents/`                                                      | Roles with fixed tools: four reviewers, a doc reviewer, a researcher, a cross-repo navigator, one writer. | Keep the roles; rewrite what each checks                                                 |
| Ledger        | `ledger/`                                                      | A map of repos, packages, environments and the edges between them.                                        | Keep the schema; write the content                                                       |
| How-to guides | `docs/how-to/`                                                 | Short process docs, each listing the source files it summarises.                                          | Write                                                                                    |
| Doctor        | `scripts/doctor.sh`                                            | Checks a machine's prerequisites.                                                                         | Write                                                                                    |
| Stack copies | `scripts/stack.sh` | Creates a renamed copy of the plugin for another stack and refreshes its core files. | Copy |
| Mods          | not in this repo                                               | Optional enforcement and UI on top.                                                                       | Optional; the mod API is early access                                                    |

## The step types

| Type       | Does                                                                                             |
| ---------- | ------------------------------------------------------------------------------------------------ |
| `instruct` | Claude does the work after loading the step's skills; with `delegate`, a declared agent does it. |
| `agents`   | Spawns declared agents in parallel and merges their reports.                                     |
| `check`    | Runs the profile's commands; with `fix`, fixes root causes and re-runs.                          |
| `gate`     | Asks the person and waits.                                                                       |
| `artifact` | Writes a story, plan or bug spec from a template.                                                |
| `vcs`      | Commits, pushes or opens a merge request.                                                        |
| `workflow` | Runs another workflow inline, optionally in another repo's clone.                                |
| `loop`     | Repeats nested steps until a condition holds, up to a maximum.                                   |

## The rules that make it work

1. **Declare everything.** A workflow lists every skill it loads and every
   agent it spawns, with the model. The validator rejects anything undeclared.
2. **Gate everything outward.** A step that pushes, opens a merge request,
   deploys or changes another repo is marked `outward` and must name the gate
   that allowed it.
3. **Enforce read-only in code.** Reviewers get read-only tools, and a hook
   denies edits and commands outside an allowlist. Asking is not enough.
4. **Keep workflows portable with profiles.** A workflow says `typecheck`;
   the profile says what that means in each repo.
5. **Keep specs short and hand them on.** Stories, plans and bug specs have
   line limits and hold no code. The implementer and every reviewer are given
   their paths.
6. **Treat the map as a map.** The ledger and guides record what was true
   when surveyed. Agents confirm against source before acting.
7. **Review in a loop with a cheap inner check.** Parallel reviewers, a
   delegated fix, a targeted re-check of that fix, then the next full pass.
8. **Log every run.** Each run keeps a log so `resume` can continue it in a
   new session.

## Port it in five steps

1. Copy the command, engine spec, templates, validator and hooks unchanged.
   `scripts/stack.sh new <name> <dir>` makes the copy under its own plugin
   name, and `scripts/stack.sh update <dir>` refreshes those files later.
2. Write one profile per repo, with commands you have run by hand, or run
   `init` inside the repo to have it detect, run and propose them.
3. Point `feature`, `bugfix`, `review` and `docs` at your profiles and run
   each once.
4. Write the skills for your stack, checked against the versions you run.
5. Build the ledger. Add a stack-specific workflow only when a task repeats.

Run the validator after each step:

```bash
ruby scripts/validate.rb && claude plugin validate .
```

## What to expect

- **Skills go stale first.** A review of the plugin this one is modelled on
  found 23 wrong statements in its skills, mostly from a framework migration
  that was never propagated. Re-check skills against installed versions on a
  schedule.
- **Most of it is instruction-driven.** Only the read-only guard and the
  validator are hard enforcement.
- **Define semantics early.** The original's workflows used step statuses and
  failure behaviour before the engine defined them. Here they are in
  `engine/engine.yaml` under `statuses` and `failure`; extend those before
  adding a workflow that needs more.
- **Check facts against the real repos.** Commands, paths and URLs in
  profiles and workflows drift; verify them against each repo's default
  branch.
