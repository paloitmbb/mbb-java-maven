<!-- Inspired by: https://github.com/github/awesome-copilot/blob/main/instructions/java.instructions.md -->
---
applyTo: '**'
description: 'Code review standards and GitHub pull request review guidelines'
---

# Code Review Standards

## Pull Request Requirements

- Every PR must pass the full pr-validation workflow (Checkstyle, SpotBugs, JaCoCo ≥ 80%, license check, SAST, secrets scan) before requesting review.
- PR titles must follow the Conventional Commits format (`type(scope): description ≤ 50 chars`).
- Include a brief description of **what changed and why**; reference the GitHub issue or JIRA ticket in the PR body.
- Keep PRs focused — one feature or fix per PR; split large changes into logical, independently reviewable units.

## Reviewer Responsibilities

- Review within one business day of assignment; communicate delays proactively.
- Verify architectural consistency: controllers must not import repositories directly.
- Confirm new public methods have Javadoc with `@param` and `@return` tags.
- Check that test coverage is adequate — happy path, null/empty input, and edge cases covered.
- Flag security concerns (hardcoded secrets, missing input validation, unsafe deserialisation) as blocking issues.

## Review Comment Etiquette

- Prefix comments with a severity indicator: **`[blocking]`**, **`[suggestion]`**, or **`[nit]`**.
- Explain the *why* behind blocking comments; link to relevant guidelines or ADRs.
- Approve only when all blocking comments are resolved; use "Request Changes" for blocking issues.
- Distinguish stylistic preferences (nits) from correctness/security concerns — do not block on nits alone.

## Architecture & Design Checks

- Confirm the `controller → service → repository → domain` layered boundary is respected.
- Ensure new exceptions extend the project's custom exception hierarchy (`ResourceNotFoundException`, `BusinessException`).
- Validate that no Java 14–21 features (records, sealed classes, pattern matching, text blocks) are used — the target is Java 11.
- Check that DTOs are used for request/response payloads and entities are never exposed directly via controllers.

## Documentation Updates

- If the PR modifies public behaviour, commands, or configuration, confirm `README.md` and relevant `docs/` files are updated.
- New architecturally significant decisions must be accompanied by an ADR in `docs/adr/`.
