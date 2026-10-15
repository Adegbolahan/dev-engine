---
template: bug
max_lines: 50
---

# Bug: <short title>

## Observed

<What happens, with the exact error text if there is one.>

## Expected

<What should happen instead.>

## Reproduction

1. <The shortest steps that show the bug, as actually run.>

## Root cause

<path:line — why it happens, confirmed by reading or running the code. No code.>

## Fix

<What will change, in words, and why that removes the cause and not only the symptom.>

## Regression test

<Where the test goes and what it asserts. It must fail before the fix.>

## Repos

- <Each repo the fix changes, by profile name, in the order they must be pushed. One line if only this repo.>

## Blast radius

- <Other callers or paths the cause or the fix touches.>
