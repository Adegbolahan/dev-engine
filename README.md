# dev-engine

A Claude Code plugin that runs gated, repeatable development workflows. One
command, `/dev`, walks a workflow written in YAML: what Claude does, in what
order, with which skills, agents and models, and where a person must approve.

The engine is instructions, not code. Claude reads `engine/engine.yaml` and a
workflow and follows them. Two things are enforced in code: reviewer agents
are read-only (a hook denies their edits and commands), and
`scripts/validate.rb` rejects a plugin whose parts disagree.

## Install

Install it once from GitHub and use it in every repo:

```bash
claude plugin marketplace add Adegbolahan/dev-engine
claude plugin install dev-engine@dev-engine
```

Updates replace the installed copy. Nothing you set up lives in it: each
repo keeps its own profile and your ledger lives in your config directory
(see "Set up a repo").

If you installed an earlier local copy as `dev-engine@dev-engine-local`,
uninstall it and add the marketplace again as above: the marketplace is now
named `dev-engine`.

To work on the plugin itself, load it from a clone instead:

```bash
claude --plugin-dir /path/to/dev-engine
```

## Use it

Inside a repo that has a profile:

| Command                           | Does                                                                                                                                       |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `/dev list`                       | Lists the workflows and this repo's profile.                                                                                               |
| `/dev init`                       | Sets up the current repo: detects and runs its commands, then writes its `.claude/dev-engine.yaml` and its ledger entry after you approve. |
| `/dev feature <what to build>`    | Story, plan, build, checks, review, merge request.                                                                                         |
| `/dev bugfix <the bug>`           | Reproduce, root cause, failing test, fix, checks, review, merge request.                                                                   |
| `/dev review [base branch]`       | Four parallel reviewers, a delegated fix, a targeted re-check, repeated until clean.                                                       |
| `/dev docs <what to document>`    | Survey the source, write, doc review, merge request.                                                                                       |
| `/dev ui-design <what to design>` | Research the app and comparable apps, discovery questions, design brief, build or mock, UI review, merge request.                          |
| `/dev resume [run-id]`            | Continues an unfinished run from its log.                                                                                                  |
| `/dev doctor`                     | Checks this machine and validates the plugin.                                                                                              |
| `/dev drift [--fetch]`            | Compares your ledger, each repo's profile and the paths its stack skills cite with the repos on this machine.                              |

Every push and merge request waits behind a gate. A run keeps its log and its
story, plan or bug spec under `.dev-engine/` in the repo it works on.

## Set up a repo

Each repo describes itself, and the plugin holds nothing about your repos:

- **Profile**: `.claude/dev-engine.yaml` in the repo, committed with it. It
  holds one profile: `name`, `description`, `base_branch`, `forge`, the
  `commands` for each command key (null where one does not apply), and
  optionally `commit_hook` and `workspace`. Its presence is what sets the
  repo up. This repo's own `.claude/dev-engine.yaml` is an example.
- **Stack skills**: the repo's `.claude/skills/`, where Claude Code finds
  them.
- **Ledger**: one file per person, mapping your repos, packages,
  environments and the edges between them. It lives at
  `~/.config/dev-engine/ledger.yaml`, or wherever `DEV_ENGINE_LEDGER`
  points. A single repo needs none.
- **Trust record**: `~/.config/dev-engine/trusted.yaml`. A profile holds
  shell commands and arrives with any repo you clone, so `/dev` shows an
  untrusted profile's commands and asks before running any. Approving
  records the SHA-256 of the profile file; any later edit to it asks again.
  Approval covers the command strings, not the scripts they call, and it is
  enforced by the `/dev` instructions rather than by a hook. Record one by
  hand with `ruby /path/to/dev-engine/scripts/config.rb trust <repo>`.

`locations` in `engine/engine.yaml` gives the schema of these files. To set
up a repo:

1. Run `/dev init` inside it. It works out the repo's commands, runs them,
   and once you approve writes `.claude/dev-engine.yaml` and adds the repo
   to your ledger, creating the ledger if it does not exist.
2. Commit `.claude/dev-engine.yaml`.
3. Add the edges between repos to your ledger as you confirm them.

From the repo, check the plugin, the repo's profile and your ledger with:

```bash
ruby /path/to/dev-engine/scripts/validate.rb
```

## What is in here

| Path                           | Holds                                                                                                         |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------- |
| `commands/dev.md`              | The `/dev` command: reads the engine, a profile and a workflow, then walks the steps.                         |
| `engine/engine.yaml`           | The eight step types and the rules, statuses and failure behaviour every run obeys.                           |
| `engine/templates/`            | Story, plan, bug spec and design brief formats, each with a line limit.                                       |
| `workflows/`                   | `feature`, `bugfix`, `review`, `docs`, `ui-design`.                                                           |
| `agents/`                      | Ten read-only agents and one writer.                                                                          |
| `skills/`                      | `effective-documentation`, `mr-description`, `repo-claude-md`, `ui-ux-design`.                                |
| `hooks/hooks.json`             | Wires the three hooks below into Claude Code.                                                                 |
| `scripts/guard-agents.sh`      | The read-only guard: denies edits and non-allowlisted commands for read-only agents.                          |
| `scripts/guard-agents.test.sh` | The guard's tests; the validator runs them.                                                                   |
| `scripts/guard-gates.sh`       | The gate guard: denies pushes and merge requests while a run's gate is unapproved.                            |
| `scripts/guard-gates.test.sh`  | The gate guard's tests; the validator runs them.                                                              |
| `scripts/session-start.sh`     | The start-of-session note in repos that have a profile.                                                       |
| `scripts/config.rb`            | Where a repo's profile, the user ledger and the trust record live; schema checks; `trust`/`trusted` commands. |
| `scripts/config.test.sh`       | Tests the session note, trust, the validator and drift against temp repos and ledgers.                        |
| `scripts/validate.rb`          | Checks schema, references, hook tests and docs as one system, plus the current repo's profile and the ledger. |
| `scripts/doctor.sh`            | Checks a machine's prerequisites and says where the ledger is.                                                |
| `scripts/drift.rb`             | Compares the ledger, each repo's profile and cited paths with the repos on this machine.                      |
| `.claude/dev-engine.yaml`      | This repo's own profile, so the engine can run its workflows on itself.                                       |
| `LICENSE`                      | MIT.                                                                                                          |

## Agents

| Agent                      | Role                                                                    | Writes |
| -------------------------- | ----------------------------------------------------------------------- | ------ |
| `correctness-reviewer`     | Logic errors, broken contracts, unhandled cases.                        | No     |
| `security-reviewer`        | Authorisation, injection, secrets, unsafe input.                        | No     |
| `test-reviewer`            | Whether tests would fail if the change were wrong.                      | No     |
| `maintainability-reviewer` | Duplication, needless complexity, broken conventions.                   | No     |
| `doc-reviewer`             | Docs checked against the source they describe.                          | No     |
| `researcher`               | Finds and reads the relevant code; proposes nothing.                    | No     |
| `cross-repo-navigator`     | Follows the ledger across repos and confirms each edge.                 | No     |
| `ui-researcher`            | Surveys the current app's UI and answers discovery questions from code. | No     |
| `prior-art-researcher`     | Studies named and comparable apps and UI patterns on the web.           | No     |
| `ui-reviewer`              | Checks a UI against its design brief and the UI checklist.              | No     |
| `implementer`              | Implements approved plans, bug specs and review findings.               | Yes    |

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
