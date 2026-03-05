<!-- Inspired by: https://github.com/github/awesome-copilot/blob/main/instructions/java.instructions.md -->
---
applyTo: '**/*.java,**/*.md'
description: 'Documentation standards for the Java/Maven project'
---

# Documentation Guidelines

## Javadoc Standards

- All public classes and public methods **must** have Javadoc.
- Class-level Javadoc: one-line summary sentence; no `@author` tag.
- Method-level Javadoc: include `@param` (one per parameter) and `@return` tags; add `@throws` for checked exceptions.
- Javadoc must describe **intent and contract**, not re-state the method name in prose.
- Keep inline comments (`//`) for non-obvious logic only; remove commented-out code before committing.

## Markdown / Project Docs

- `README.md` must stay current: update it whenever public behaviour, commands, or configuration changes.
- Architecture decisions go in `docs/adr/` using the standard ADR format (Context → Decision → Consequences).
- CI/CD behaviour or workflow changes must be reflected in `docs/cicd-pipeline-guide.md`.
- Diagrams live in `docs/diagrams/`; API specifications in `docs/api/`.

## Change Documentation

- Every PR that changes observable behaviour or configuration must include a documentation update.
- Commit messages follow the Conventional Commits format as defined in `.github/instructions/git.instructions.md`.
- When adding a new feature, update the relevant ADR or create a new one if the decision is architecturally significant.
