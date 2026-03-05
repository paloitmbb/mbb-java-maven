---
agent: 'agent'
model: Claude Sonnet 4.5
tools: ['codebase', 'search', 'usages']
description: 'Scaffold a new Java class or component following project architecture conventions'
---

# Set Up New Java Component

Your goal is to scaffold a new Java class or component that is consistent with the existing project architecture.

Ask for the following information if not provided:
- **Component name** (e.g., `UserService`, `OrderController`)
- **Layer** (controller, service, service/impl, repository, domain/entity, domain/dto, domain/mapper, exception, util)
- **Purpose** (brief description of what the component does)

## Requirements

- Place the class in the correct package under `src/main/java/com/example/` based on the layer.
- Add a class-level Javadoc comment (one-line summary, no `@author`).
- Add `@param` and `@return` Javadoc tags to all public methods.
- Follow the naming conventions in `.github/instructions/java.instructions.md`: `UpperCamelCase` for classes, `lowerCamelCase` for methods.
- Use Java 11 features only — no records, sealed classes, pattern matching, or text blocks.
- Respect the architectural boundary: controllers must not import repositories directly.
- If creating a service, produce both an interface in `service/` and an implementation in `service/impl/`.
- After scaffolding the component, create a corresponding test class in the mirrored `src/test` package.
- Null-guard every method parameter that accepts strings or objects using `if (x == null || x.isEmpty())` pattern.
