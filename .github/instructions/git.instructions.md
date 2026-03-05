---
applyTo: '**'
---

# Workspace Git Guidelines

High-level commit standards for every project inside this mono-repo. Follow these rules whenever you stage or describe changes, regardless of subdirectory.

## Core Principles

1. **Consistency over preference** – match the shared format even if a sub-project is smaller.
2. **Single source of truth** – reference issue/PR numbers in bodies instead of subject tweaks.
3. **Readable history** – summarize intent (what + why) so reviewers can skim `git log --oneline`.

## Commit Message Template

```
<type>[optional scope]: [optional gitmoji] <short description>

[optional body — explain what changed and why]

[optional footer — references, BREAKING CHANGE, security notes]
```

- Subject line ≤ 50 characters, imperative mood, no trailing period.
- Separate body/footers from subject with a blank line and wrap at ~72 chars.
- Use lowercase for `type`, `scope`, description, and gitmoji codes.

### Conventional Commit Types

| Type | When to use |
|------|-------------|
| `feat` | Net-new behavior or capability for users/infra |
| `fix` | Bug fix, regression patch, or configuration correction |
| `docs` | README, instructions, runbooks, diagrams |
| `style` | Formatting-only changes (whitespace, comments) |
| `refactor` | Internal restructuring without behavior change |
| `perf` | Performance optimizations |
| `test` | Adding or updating automated tests |
| `build` | Dependencies, build tooling, package bumps |
| `ci` | Workflow, pipeline, or automation updates |
| `chore` | Misc maintenance outside src/tests |
| `revert` | Explicit rollback of a previous commit |

> Use scopes (e.g., `feat(stacks): …`) to highlight the impacted area (`stacks`, `java`, `node`, `python`, `terraform`, `docs`, etc.).

### Optional Gitmoji Placement

`<type>(scope): :gitmoji: description`

Common choices: `:sparkles:` for features, `:bug:` for fixes, `:memo:` for docs, `:white_check_mark:` for tests. Skip emojis when unclear.

## Commit Body Expectations

- **What changed?** Summarize the major edits or files touched.
- **Why?** Mention issues, incidents, or motivations.
- **How to verify?** List key commands or tests that validate the change.
- **References:** Use `Closes #123`, `Related: JIRA-456`, or `BREAKING CHANGE:` footers.

## Branch Hygiene & PR Tips

1. Keep branches focused (one feature/fix). Squash on merge unless the history is intentionally sequential.
2. Rebase over merge when syncing with main to keep linear history.
3. Before opening a PR, ensure:
   - CI scripts/tests run locally (`./scripts/*` or `npm test` equivalents).
   - Docs updated when behavior/config changes (see update-docs instructions).
   - Sensitive data never enters commit history.

## Examples

```
feat(stacks): :sparkles: add java stack template

add devcontainer, ci workflow, readme, and gitignore for java stack

Closes #12
```

```
fix: :bug: handle terraform plan failure exit codes

retry exit code 1 scenarios so CI surfaces actionable logs.
```

```
docs(workflows): :memo: clarify tfsec + trivy scanners

explain why checkov was removed and point to memory instructions.
```

## Review Checklist

- Does the subject describe intent succinctly?
- Are related issues mentioned in body/footers?
- Did you run lint/tests/scripts relevant to the change?
- Are docs updated per `.github/instructions/update-docs-on-code-change.instructions.md`?

Follow these guidelines consistently across all changes in this repository.
