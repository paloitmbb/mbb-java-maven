---
agent: 'copilot-coding-agent'
model: Claude Sonnet 4.5
tools: ['codebase', 'search', 'usages', 'findTestFiles', 'edit/editFiles']
description: 'Improve JUnit 4 tests in an existing test file to increase coverage and quality'
---

# Write Tests

Your goal is to improve the **existing** test file for a given Java class, adding missing test cases to satisfy the project's coverage and quality requirements. **Do not create a new test file** — always locate and edit the existing one.

Ask for the following information if not provided:
- **Class to test** (fully qualified name or file path)
- **Scenarios to cover** (if specific edge cases should be prioritised)

## Requirements

- Use `findTestFiles` to locate the existing test file before making any edits.
- Add new test methods to the **existing** test file; never create a replacement file.
- Use **JUnit 4.13.2** exclusively: import `org.junit.Test` and `static org.junit.Assert.*`. Never use JUnit 5 / Jupiter annotations.
- Follow the existing naming convention in the file: `test<Method><Scenario>` in camelCase (e.g., `testGetGreetingWithNull`, `testGetGreetingWithValidName`).
- Instantiate the class under test fresh inside each test method unless a non-trivial shared setup is already present.
- Use `assertEquals(expected, actual)` — expected value **always** first.
- Add coverage for any missing scenarios: happy path, `null` input, empty/boundary input for every method accepting strings or collections.
- Do not duplicate test methods that already exist — check first with `codebase`.
- Do not use `Thread.sleep`; avoid shared mutable state between tests.
- Ensure the updated test file keeps JaCoCo line coverage at or above 80% for the class under test.
