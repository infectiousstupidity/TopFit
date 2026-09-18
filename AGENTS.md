# Agent Instructions

## Defaults

- Keep changes small and direct.
- Prefer simple solutions over abstractions.
- This addon targets World of Warcraft 3.3.5a, Interface 30300, and Lua 5.1.
- Do not introduce APIs or Lua syntax newer than the 3.3.5 client supports.
- Treat `Libs/` as vendored third-party code. Do not reformat or refactor it as part of normal work.
- Follow `.github/commit-instructions.md`.

## Quality gate

GitHub Actions is the canonical repository gate.

Before committing Lua changes:

1. Check Lua 5.1 syntax with `luac5.1 -p`.
2. Run StyLua 2.5.2 in check mode on changed first-party Lua files.
3. Run Luacheck 1.2.0 on changed first-party Lua files.
4. Run `git diff --check`.

Do not create or merge a change that knowingly fails the repository checks.

## Code changes

- Preserve behavior unless the task explicitly changes it.
- Prefer extracting focused modules over growing already-large files.
- Keep WoW API interaction at clear boundaries where practical.
- Avoid adding framework or tooling layers that do not solve a current problem.
- Add tests when logic can be exercised outside the WoW client.
