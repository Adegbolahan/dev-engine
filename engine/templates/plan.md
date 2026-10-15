---
template: plan
max_lines: 60
---

# Plan: <short title>

## Approach

<Three to five sentences on how the story will be met and why this way.>

## Existing code to reuse

- <path — what it already does that this work builds on.>

## Changes

1. <path — what changes there, in words. No code.>

## Tests

- <Which acceptance criterion each new or changed test proves, and where it lives.>

## Risks

- <What could go wrong, and how the plan limits it.>

## Repos

- <Each repo this work changes, by profile name, in the order they must be pushed: a repo before the repos that depend on it. One line if only this repo.>

## Rollback

<Required when the change touches a migration, infrastructure or a deploy setting: how it is undone, and how that undo was checked. Otherwise "Not needed", with the reason.>

## Order of work

1. <Steps small enough that the checks pass after each.>
