---
agent: 'agent'
model: Claude Sonnet 4.5
tools: ['codebase', 'search', 'usages']
description: 'Generate or update documentation for a Java class, feature, or architectural decision'
---

# Generate Documentation

Your goal is to generate or update documentation consistent with the project’s standards in `.github/instructions/documentation.instructions.md`.

Ask for the following information if not provided:
- **Documentation type**: Javadoc, README update, ADR, API spec, or CI/CD guide update
- **Target**: class/method to document, feature to describe, or decision to record

## Javadoc Generation

- Add class-level Javadoc with a one-line summary (no `@author`).
- Add `@param`, `@return`, and `@throws` tags to all public methods.
- Describe *intent and contract*, not just the method name restated.

## README Updates

- Update `README.md` whenever public behaviour, commands, or configuration changes.
- Keep the Quick Start section accurate with current Maven commands (`mvn clean verify`, `mvn test`).
- Document any new environment variables or secrets required.

## Architecture Decision Record (ADR)

When recording an architectural decision, structure the ADR file in `docs/adr/` as:
1. **Context** — what situation or problem prompted the decision
2. **Decision** — what was decided
3. **Consequences** — trade-offs, follow-up actions, impact on existing code

## CI/CD Pipeline Guide Updates

- Update `docs/cicd-pipeline-guide.md` when workflow behaviour, job names, approval requirements, or secret names change.
- Note that `name: CI` and `name: Container` must never be renamed (downstream trigger dependency).
