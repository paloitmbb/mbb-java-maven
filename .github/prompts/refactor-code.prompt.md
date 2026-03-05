---
agent: 'agent'
model: Claude Sonnet 4.5
tools: ['codebase', 'search', 'usages', 'findTestFiles']
description: 'Safely refactor Java code while preserving behaviour and maintaining test coverage'
---

# Refactor Code

Your goal is to safely refactor Java code, improving structure and readability without changing observable behaviour.

Ask for the following information if not provided:
- **Target** (file(s) or class(es) to refactor)
- **Refactoring goal** (e.g., extract method, simplify conditionals, reduce duplication, improve naming)

## Requirements

- **Do not change observable behaviour** — all existing tests must pass after the refactoring.
- Use only Java 11 features; do not introduce Java 14–21 constructs.
- Respect the architectural layering: `controller → service → repository → domain`.
- Maintain or improve Javadoc on all public methods after renaming or restructuring.
- After completing the refactoring, verify that JaCoCo line coverage remains at or above 80%.
- If the refactoring changes a public API (method signature, class name), update all usages identified via the `usages` tool.
- Identify and find all callers of modified methods before changing signatures.
- Prefer extracting well-named private methods for repeated or complex logic blocks.
- Make arguments and fields `final` where possible to signal immutability.
- Remove dead code, unused imports, and suppressed warnings that are no longer relevant.

## Output

Provide a summary of changes made, list any methods whose signatures changed, and confirm that all test files remain valid.
