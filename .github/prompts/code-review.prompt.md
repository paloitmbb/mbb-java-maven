---
agent: 'agent'
model: Claude Sonnet 4.5
tools: ['codebase', 'search', 'usages', 'githubRepo']
description: 'Perform a thorough code review of staged changes or a specified file'
---

# Code Review

Your goal is to perform a thorough code review that matches the standards in `.github/instructions/code-review.instructions.md`.

Ask for the following information if not provided:
- **Target** (file path, PR diff, or describe the change to review)

## Review Checklist

Evaluate the code against these areas and prefix each finding with **`[blocking]`**, **`[suggestion]`**, or **`[nit]`**:

### Architecture & Boundaries
- Confirm the `controller → service → repository → domain` layered boundary is respected.
- No Java 14–21 features (records, sealed classes, text blocks, pattern matching) — target is Java 11.
- DTOs used for controller payloads; entities are never returned directly.

### Code Quality
- All public methods have Javadoc with `@param` and `@return` tags.
- Null/empty guards are present for string and object parameters.
- No commented-out code or debug print statements committed.
- Exceptions are specific and extend the project’s custom hierarchy.

### Testing
- New code has corresponding JUnit 4 tests covering happy path, null, and boundary inputs.
- JaCoCo coverage for the changed classes is at or above 80%.

### Security
- No hardcoded credentials, tokens, or secrets.
- External input validated before use.
- Dependencies with known CVEs are not introduced.

### Documentation
- If public behaviour changed, `README.md` and relevant `docs/` files are updated.
- Architecturally significant decisions are recorded in `docs/adr/`.

Provide a concise summary at the end with a recommended decision: **Approve**, **Approve with suggestions**, or **Request changes**.
