---
name: repo-claude-md
description: How to write or revise a repository's CLAUDE.md so it holds what Claude cannot work out from the code. Load before creating or editing a CLAUDE.md, or when a dev-engine step lists it.
---

# A repo's CLAUDE.md

CLAUDE.md is loaded into every session in the repo. Every line costs context
each time, so a line belongs only if a session would go wrong without it.

## What belongs

- **Commands**: how to install, typecheck, lint, test (including one test)
  and run locally, exactly as typed. Keep them the same as this repo's entry
  in `engine/profiles.yaml`.
- **Layout that is not obvious**: where things live when the directory names
  do not say, and which directories are generated or vendored.
- **Rules the code does not show**: conventions a newcomer would break, such
  as "never edit migrations after merge" or "all API calls go through this
  client".
- **Traps**: things that look right and are wrong here, with the right way.
- **Boundaries**: what must not be touched or run without asking.

## What does not belong

- Anything the code, the README or `git log` already says.
- General advice ("write clean code", "add tests").
- A file-by-file tour, or anything that goes stale with every commit.
- Secrets, tokens or personal data.

## How to write it

- Imperative and specific: "Run `pnpm test -- <file>` for one test file."
- Give the reason with a rule when the reason is not obvious; a rule with a
  reason is followed in the cases the rule did not foresee.
- Short sections with plain headings. Aim for under about 100 lines.
- Run every command before writing it down.
- When revising, delete what is no longer true before adding anything.
