<!-- Inspired by: https://github.com/github/awesome-copilot/blob/main/instructions/java.instructions.md -->
---
applyTo: '**/*.java'
description: 'Performance optimisation guidelines for the Java/Maven project'
---

# Performance Guidelines

## General Java Performance

- Prefer `StringBuilder` over string concatenation inside loops; avoid repeated `+` on `String` in hot paths.
- Use the Streams API for readability but be aware of boxing overhead in performance-sensitive code — measure before optimising.
- Favour immutable collections (`List.of()`, `Map.of()`) for fixed data sets; they avoid defensive copy overhead.
- Close resources eagerly with try-with-resources to prevent memory and file-descriptor leaks.
- Avoid unnecessary object creation in tight loops; reuse where safe and the intent is clear.

## Algorithm & Data Structure Choices

- Choose the right collection type: `ArrayList` for index-heavy access, `LinkedList` for frequent insertion/removal, `HashMap`/`HashSet` for O(1) lookups.
- Sort only when ordering is actually needed; avoid re-sorting unchanged data.
- Prefer lazy evaluation and early-exit patterns (`Optional.orElseGet`, `Stream.findFirst`) over computing the full result set.

## Build & Startup Performance

- Keep the compile-time classpath lean; remove unused dependencies from `pom.xml`.
- The Maven Surefire plugin (2.22.2) runs tests in forked JVMs — ensure test isolation does not introduce unnecessary JVM forks.

## Observability

- Record baseline performance metrics before refactoring and validate improvement with a repeatable benchmark.
- Log at the appropriate level: DEBUG for diagnostic paths, INFO for key lifecycle events; avoid verbose logging in hot paths.
- Use structured logging where possible to make log ingestion efficient in centralised systems.
