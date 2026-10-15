# dev-engine

A Claude Code plugin that runs gated, repeatable development workflows. One
command, `/dev`, walks a workflow written in YAML: what Claude does, in what
order, with which skills, agents and models, and where a person must approve.

The engine is instructions, not code. Claude reads `engine/engine.yaml` and a
workflow and follows them. Two things are enforced in code: reviewer agents
are read-only (a hook denies their edits and commands), and
`scripts/validate.rb` rejects a plugin whose parts disagree.

## Use it

Load the plugin from this directory:

```bash
claude --plugin-dir /path/to/dev-engine
```

Or install it for every session, from the local marketplace defined in
`.claude-plugin/marketplace.json`:

```bash
claude plugin marketplace add /path/to/dev-engine
claude plugin install dev-engine@dev-engine-local
```

After changing the plugin, run `claude plugin marketplace update
dev-engine-local`, then `/reload-plugins`.

Then, inside a repo that has a profile:

| Command                        | Does                                                                                 |
| ------------------------------ | ------------------------------------------------------------------------------------ |
| `/dev list`                    | Lists the workflows and the profile this repo matches.                               |
| `/dev init` | Adds the current repo to the plugin: detects and runs its commands, then writes its profile and ledger entry after you approve. |
| `/dev feature <what to build>` | Story, plan, build, checks, review, merge request.                                   |
| `/dev bugfix <the bug>`        | Reproduce, root cause, failing test, fix, checks, review, merge request.             |
| `/dev review [base branch]`    | Four parallel reviewers, a delegated fix, a targeted re-check, repeated until clean. |
| `/dev docs <what to document>` | Survey the source, write, doc review, merge request.                                 |
| `/dev ui-design <what to design>` | Research the app and comparable apps, discovery questions, design brief, build or mock, UI review, merge request. |
| `/dev resume [run-id]`         | Continues an unfinished run from its log.                                            |
| `/dev doctor`                  | Checks this machine and validates the plugin.                                        |
| `/dev drift [--fetch]`         | Compares profiles, the ledger and cited paths with the repos on this machine.        |

Every push and merge request waits behind a gate. A run keeps its log and its
story, plan or bug spec under `.dev-engine/` in the repo it works on.

## One copy per stack

Profiles, stack skills and the ledger describe one system. Keep one copy of
the plugin per stack, meaning per group of repos that belong together, and
leave this one as the base they are made from.

```bash
scripts/stack.sh new acme-engine ~/Code/acme-engine   # create a copy
scripts/stack.sh update ~/Code/acme-engine            # refresh its core later
```

A copy takes its own plugin name, so its command is `/acme-engine:dev`, its
agents are `acme-engine:<agent>` and its run state lives in `.acme-engine/`
in each repo. Copies can be installed side by side.

`update` replaces only the core a stack does not edit: the command, the
engine spec, the templates, `hooks/hooks.json`, the validator, the
session-start script and `stack.sh` itself. Profiles, the ledger, workflows,
agents, skills, the guard's agent list, the doctor and the docs belong to the
stack and are left alone. Change the core here, then update each copy.

## Add your repos

A copy starts with one profile, for itself. To use it on your repos:

1. Run `/dev init` inside each repo. It works out the repo's commands, runs
   them, and writes the profile in `engine/profiles.yaml` and the repo entry
   in `ledger/ledger.yaml` once you approve. Both can also be written by
   hand; the profiles file has a template.
2. Add the edges between repos to `ledger/ledger.yaml` as you confirm them.
3. Write skills for your stack under `skills/` and declare them in the
   workflows that need them.
4. Add your stack's prerequisites to `scripts/doctor.sh`.

Run the validator after each change:

```bash
ruby scripts/validate.rb && claude plugin validate .
```

`docs/how-to/build-your-own-plugin.md` explains the design and how to port
it.

## What is in here

| Path                           | Holds                                                                                 |
| ------------------------------ | ------------------------------------------------------------------------------------- |
| `commands/dev.md`              | The `/dev` command: reads the engine, a profile and a workflow, then walks the steps. |
| `engine/engine.yaml`           | The eight step types and the rules, statuses and failure behaviour every run obeys.   |
| `engine/profiles.yaml`         | Per repo: how to recognise it, its base branch, forge and commands.                   |
| `engine/templates/`            | Story, plan, bug spec and design brief formats, each with a line limit.               |
| `workflows/`                   | `feature`, `bugfix`, `review`, `docs`, `ui-design`.                                   |
| `agents/`                      | Ten read-only agents and one writer.                                                  |
| `skills/`                      | `effective-documentation`, `mr-description`, `repo-claude-md`, `ui-ux-design`.        |
| `hooks/hooks.json`             | Wires the three hooks below into Claude Code.                                         |
| `scripts/guard-agents.sh`      | The read-only guard: denies edits and non-allowlisted commands for read-only agents.  |
| `scripts/guard-agents.test.sh` | The guard's tests; the validator runs them.                                           |
| `scripts/guard-gates.sh`       | The gate guard: denies pushes and merge requests while a run's gate is unapproved.    |
| `scripts/guard-gates.test.sh`  | The gate guard's tests; the validator runs them.                                      |
| `scripts/session-start.sh`     | The start-of-session note in repos that match a profile.                              |
| `scripts/validate.rb`          | Checks schema, references, hook tests and docs as one system.                         |
| `scripts/doctor.sh`            | Checks a machine's prerequisites.                                                     |
| `scripts/drift.rb`             | Compares profiles, the ledger and cited paths with the repos on this machine.         |
| `scripts/stack.sh`             | Creates a copy of the plugin for another stack and refreshes its core.                |
| `ledger/ledger.yaml`           | The map of repos, packages, environments and edges.                                   |
| `docs/how-to/`                 | Process guides, each listing the source files it summarises.                          |

## Agents

| Agent                      | Role                                                      | Writes |
| -------------------------- | --------------------------------------------------------- | ------ |
| `correctness-reviewer`     | Logic errors, broken contracts, unhandled cases.          | No     |
| `security-reviewer`        | Authorisation, injection, secrets, unsafe input.          | No     |
| `test-reviewer`            | Whether tests would fail if the change were wrong.        | No     |
| `maintainability-reviewer` | Duplication, needless complexity, broken conventions.     | No     |
| `doc-reviewer`             | Docs checked against the source they describe.            | No     |
| `researcher`               | Finds and reads the relevant code; proposes nothing.      | No     |
| `cross-repo-navigator`     | Follows the ledger across repos and confirms each edge.   | No     |
| `ui-researcher`            | Surveys the current app's UI and answers discovery questions from code. | No |
| `prior-art-researcher`     | Studies named and comparable apps and UI patterns on the web. | No |
| `ui-reviewer`              | Checks a UI against its design brief and the UI checklist. | No     |
| `implementer`              | Implements approved plans, bug specs and review findings. | Yes    |

Read-only is enforced twice: the agents' tool lists hold no write tools, and
the `PreToolUse` hook denies edits and any Bash command outside the allowlist
in `scripts/guard-agents.sh`.

## Limits

- Gates, declared models and step order are followed because the command
  tells Claude to follow them. Only the read-only guard and the validator are
  hard enforcement.
- The guard does not parse shell quoting. A reviewer's command with a pipe or
  redirect character inside a quoted pattern is denied; it has the Grep tool
  for those.
- The ledger and guides are maps of what was true when surveyed. Agents are
  told to confirm against source before acting.
