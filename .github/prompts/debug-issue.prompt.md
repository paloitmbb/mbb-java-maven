---
agent: 'agent'
model: Claude Sonnet 4.5
tools: ['codebase', 'search', 'usages', 'terminalCommand']
description: 'Diagnose and fix a bug or failing test in the Java/Maven project'
---

# Debug Issue

Your goal is to systematically diagnose and resolve a bug or failing test in this Java/Maven project.

Ask for the following information if not provided:
- **Symptom** (error message, stack trace, failing test name, or unexpected behaviour)
- **Reproduction steps** (command or scenario that triggers the issue)

## Debugging Process

### 1. Reproduce
- Identify the specific failing test or behaviour.
- Run `mvn test` (or `mvn test -pl . -Dtest=<TestClass>`) to confirm the failure.

### 2. Locate the Root Cause
- Use the `codebase` and `search` tools to trace the call path from the failing assertion back to the originating logic.
- Check null/empty guard conditions — a common source of `NullPointerException` in this project.
- Verify the expected vs. actual values in `assertEquals(expected, actual)` are in the correct order.

### 3. Analyse the Stack Trace
- Identify the exact line number and class where the exception originates.
- Distinguish between root cause and secondary failures caused by the root issue.

### 4. Fix
- Apply the minimal change that resolves the root cause without changing unrelated behaviour.
- Stay within Java 11 language features.
- Ensure the fix does not reduce JaCoCo line coverage below 80%.

### 5. Verify
- Confirm the previously failing test now passes.
- Run the full test suite (`mvn clean verify`) to ensure no regressions.

## Output

Provide: root cause explanation, the fix applied, and confirmation that the full test suite passes.
