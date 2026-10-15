---
name: effective-documentation
description: How to write documentation a specific reader can act on and that stays true to the source. Load before writing or revising a README, how-to guide, runbook or reference page, or when a dev-engine step lists it.
---

# Effective documentation

A doc is done when its reader can do the thing it is for, and every statement
in it is true of the source.

## Before writing

1. **Name the reader.** One kind of person, with what they already know and
   what they are trying to do. If two readers need different things, that is
   two docs.
2. **Pick the kind.** A how-to gets someone through a task. A reference
   answers lookups. An explanation says why. Do not mix them in one page.
3. **Read the source.** Open every file the doc will describe. Do not write
   from memory, from an older doc, or from what the code probably does.

## Writing

- Lead with what the reader needs first: what this is and what they can do
  with it. Background comes after, if at all.
- State facts plainly. "Run `make test`", not "you may want to consider
  running the tests".
- Give commands and paths exactly, as they would be typed, and only ones you
  have run or opened.
- Use one name for one thing, and make it the name the source uses.
- Use a table when the content has columns, a numbered list when order
  matters, and prose otherwise.
- Say each thing once. Link to the place that owns a fact instead of
  restating it.
- Leave out what the reader cannot use: history, apologies, how hard it was.
- Short is a result, not a goal. Do not drop a step the reader needs.

## How-to guides in this plugin

A guide in `docs/how-to/` starts with frontmatter listing the files it
summarises:

```yaml
---
sources:
  - engine/engine.yaml
  - workflows/feature.yaml
---
```

The validator fails when a listed source is missing, so a renamed file
surfaces the guide that needs rereading.

## Before calling it done

- Check every command, path, name and number against the source once more.
- Read it as the reader, top to bottom. Wherever you would have to guess,
  the doc is missing something.
- If the doc says the code does something and it does not, fix the doc or
  report the code. Never blur the sentence until it is not wrong.
