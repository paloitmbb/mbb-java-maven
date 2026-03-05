<!-- Inspired by: https://github.com/github/awesome-copilot/blob/main/instructions/java.instructions.md -->
---
applyTo: '**/*Test.java,**/*Tests.java,**/*IT.java'
description: 'Testing standards and practices for Java/Maven projects with JUnit 4'
---

# Testing Guidelines

## Framework & Tooling

This project uses **JUnit 4.13.2** exclusively — never JUnit 5 (Jupiter). Always import `org.junit.Test` and `static org.junit.Assert.*`. JaCoCo enforces ≥ 80% line coverage and is a hard build gate.

## Test Structure

- Mirror the `src/main` package layout exactly under `src/test`.
- Integration tests live in `src/test/.../integration/` subdirectories.
- Name test classes `<ClassUnderTest>Test` and test methods `test<Method><Scenario>` in camelCase (e.g., `testGetGreetingWithNull`).
- Instantiate the class under test fresh inside each test method unless shared setup is non-trivial; use `@Before`/`@After` only when necessary.

## Assertion Conventions

- Always put the **expected value first** in `assertEquals(expected, actual)` calls.
- Use `assertNotNull` before accessing fields on returned objects.
- Test at minimum: the happy path, `null` input, and empty/boundary input for every method accepting strings or collections.

## Coverage Requirements

- Maintain JaCoCo line coverage at or above 80% — never merge changes that drop the metric below this threshold.
- Every public method must have at least one test; private logic should be exercised through public entry points.
- Do not exclude classes from JaCoCo reports without a documented reason.

## Test Quality

- Keep tests fast, deterministic, and independent; avoid shared mutable state.
- Do not use `Thread.sleep` for timing — use mocks or Awaitility if async behaviour must be tested.
- Each test should assert only one logical outcome to produce clear failure messages.
