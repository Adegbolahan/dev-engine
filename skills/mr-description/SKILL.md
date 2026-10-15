---
name: mr-description
description: How to write a merge request or pull request title and description that a reviewer can act on. Load before opening or updating a merge request, or when a dev-engine step lists it.
---

# Merge request descriptions

The reviewer has not seen the conversation, the story or the plan. The
description is everything they get besides the diff.

## Title

One line, under about 70 characters, saying what changes for the user or the
system. Follow the repo's convention if it has one; check recent merged
requests with `git log` before inventing a format.

## Description

Use the repo's merge request template if there is one. Otherwise:

**What and why.** Two to four sentences. What the change does and the reason
for it. Link the issue or ticket if one exists.

**How.** The approach in a few sentences, and anything a reviewer would
otherwise have to work out: why this way and not the obvious other way, what
was deliberately left alone.

**How it was checked.** The commands that were run and their result, taken
from the run, and anything checked by hand. If something was not checked, say
so.

**Where to look.** The files or decisions that most need a careful read, and
any risk that remains.

## Rules

- Write it from the diff and the run log, not from memory of the plan. Say
  what the change does, not what it was meant to do.
- Do not paste the story or plan. Summarise; the reviewer reads the diff.
- No claims the run did not establish. "Tests pass" only if they ran and
  passed.
- Leave out the narrative of how the work went.
- Keep attribution trailers the tooling adds, such as `Co-Authored-By` lines.
