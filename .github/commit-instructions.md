# Commit Instructions

Use Conventional Commits.

## Format

<type>(optional-scope): <description>

## Common types

- `feat` - user-facing feature
- `fix` - bug fix
- `docs` - documentation only
- `style` - formatting only
- `refactor` - code change with no behavior change
- `perf` - performance improvement
- `test` - tests only
- `build` - build system or dependency change
- `ci` - CI workflow change
- `chore` - maintenance
- `revert` - revert a previous commit

## Rules

- Use a lowercase type.
- Use imperative mood.
- Keep the subject near 50 characters when practical; hard cap 72.
- Do not end the subject with a period.
- Use a scope only when it improves clarity.
- Use a one-line commit message by default.
- Add a body only when the reason is not obvious from the change.
- Do not generate file-by-file summaries.
- Do not add AI attribution or emoji.

## Examples

feat(optimizer): add alternate gear sets
fix(inventory): handle empty bank slots
ci: add Lua quality gates
chore: update project foundation
