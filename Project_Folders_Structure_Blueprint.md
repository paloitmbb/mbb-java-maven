# Project Folders Structure Blueprint

> **Technology**: Java · Maven
> **Architecture**: Layered / Hexagonal-friendly · Spring Boot ready
> **Last Updated**: 2026-03-02

---

## Table of Contents

1. [Structural Overview](#1-structural-overview)
2. [Directory Visualization](#2-directory-visualization)
3. [Key Directory Analysis](#3-key-directory-analysis)
4. [File Placement Patterns](#4-file-placement-patterns)
5. [Naming and Organization Conventions](#5-naming-and-organization-conventions)
6. [Navigation and Development Workflow](#6-navigation-and-development-workflow)
7. [Build and Output Organization](#7-build-and-output-organization)
8. [Java / Maven-Specific Patterns](#8-java--maven-specific-patterns)
9. [Extension and Evolution](#9-extension-and-evolution)
10. [Structure Templates](#10-structure-templates)
11. [Structure Enforcement](#11-structure-enforcement)

---

## 1. Structural Overview

### Architectural Approach

The project follows a **layered architecture** aligned with Maven's standard directory layout
(`src/main/java`, `src/test/java`).  Layers are organized by **technical concern** at the top
level and, within each layer, by **feature/domain package**. This makes the code easy to
navigate from both an infrastructure and a business perspective.

### Main Organizational Principles

| Principle | Details |
|---|---|
| **Maven Standard Layout** | All source in `src/main`, all tests in `src/test` |
| **Layer separation** | `controller → service → repository → domain` |
| **Package-by-feature** | Within each layer, sub-packages reflect domain/bounded context |
| **Fail-fast configuration** | Environment-specific properties override base `application.yml` |
| **Test mirrors source** | Test packages mirror the production package tree 1-to-1 |

### Rationale

Maven enforces a predictable layout across teams. Combining it with a layered package structure
provides clear dependency rules (controllers never import repositories directly), simplifies
onboarding, and supports incremental migration toward hexagonal architecture if needed.

---

## 2. Directory Visualization

```
mbb-java-maven/                          # Repository root
├── .devcontainer/                        # Dev container configuration
│   └── devcontainer.json
├── .github/                              # GitHub configuration
│   ├── instructions/                     # Copilot instruction files
│   ├── skills/                           # Copilot skill files
│   └── workflows/                        # CI/CD pipeline definitions
│       ├── ci.yml                        # Build, test & lint on PR/push
│       ├── release.yml                   # Release / publish workflow
│       └── security.yml                  # SAST / dependency scanning
├── .vscode/                              # VS Code workspace settings
│   ├── settings.json
│   ├── extensions.json
│   └── launch.json
├── docs/                                 # Project documentation
│   ├── adr/                              # Architecture Decision Records
│   │   └── 0001-use-layered-architecture.md
│   ├── api/                              # API documentation (OpenAPI/Swagger)
│   └── diagrams/                         # Architecture & sequence diagrams
├── scripts/                              # Build, deploy & utility scripts
│   ├── build.sh
│   ├── run-local.sh
│   └── db-migrate.sh
├── src/
│   ├── main/
│   │   ├── java/
│   │   │   └── com/example/app/          # Root package (mirrors artifact groupId)
│   │   │       ├── Application.java       # Spring Boot entry point
│   │   │       ├── config/               # Spring/framework configuration beans
│   │   │       │   ├── SecurityConfig.java
│   │   │       │   ├── WebMvcConfig.java
│   │   │       │   └── CacheConfig.java
│   │   │       ├── controller/           # REST / web layer
│   │   │       │   ├── UserController.java
│   │   │       │   └── advice/           # @ControllerAdvice / exception handlers
│   │   │       │       └── GlobalExceptionHandler.java
│   │   │       ├── service/              # Business logic interfaces
│   │   │       │   ├── UserService.java
│   │   │       │   └── impl/             # Concrete service implementations
│   │   │       │       └── UserServiceImpl.java
│   │   │       ├── repository/           # Data access layer (Spring Data / JPA)
│   │   │       │   └── UserRepository.java
│   │   │       ├── domain/               # Core business types
│   │   │       │   ├── entity/           # JPA entities / aggregates
│   │   │       │   │   └── User.java
│   │   │       │   ├── dto/              # Request/response Data Transfer Objects
│   │   │       │   │   ├── UserRequest.java
│   │   │       │   │   └── UserResponse.java
│   │   │       │   ├── enums/            # Domain enumerations
│   │   │       │   │   └── UserRole.java
│   │   │       │   └── mapper/           # Entity <-> DTO mappers (MapStruct etc.)
│   │   │       │       └── UserMapper.java
│   │   │       ├── exception/            # Custom exception classes
│   │   │       │   ├── ResourceNotFoundException.java
│   │   │       │   └── BusinessException.java
│   │   │       ├── security/             # Security components
│   │   │       │   ├── JwtTokenProvider.java
│   │   │       │   └── UserDetailsServiceImpl.java
│   │   │       └── util/                 # Stateless utility / helper classes
│   │   │           ├── DateUtils.java
│   │   │           └── StringUtils.java
│   │   └── resources/
│   │       ├── application.yml           # Base / shared configuration
│   │       ├── application-dev.yml       # Dev environment overrides
│   │       ├── application-staging.yml   # Staging environment overrides
│   │       ├── application-prod.yml      # Production environment overrides
│   │       ├── db/
│   │       │   └── migration/            # Flyway / Liquibase migration scripts
│   │       │       ├── V1__init_schema.sql
│   │       │       └── V2__add_user_table.sql
│   │       ├── static/                   # Static web assets (if serving frontend)
│   │       ├── templates/                # Server-side templates (Thymeleaf etc.)
│   │       ├── i18n/                     # Internationalisation message bundles
│   │       │   ├── messages.properties
│   │       │   └── messages_fr.properties
│   │       └── logback-spring.xml        # Logging configuration
│   └── test/
│       ├── java/
│       │   └── com/example/app/          # Mirrors main package hierarchy
│       │       ├── controller/
│       │       │   └── UserControllerTest.java
│       │       ├── service/
│       │       │   └── UserServiceTest.java
│       │       ├── repository/
│       │       │   └── UserRepositoryTest.java
│       │       └── integration/          # Full-stack / slice integration tests
│       │           └── UserIntegrationTest.java
│       └── resources/
│           ├── application-test.yml      # Test-specific config overrides
│           └── sql/                      # Test data SQL scripts
│               └── init-test-data.sql
├── target/                               # Maven build output (git-ignored)
├── .gitignore
├── pom.xml                               # Maven project descriptor
├── README.md
├── CHANGELOG.md
├── LICENSE
└── Project_Folders_Structure_Blueprint.md  # This document
```

---

## 3. Key Directory Analysis

### `src/main/java/com/example/app/`

Root application package. The group prefix (`com.example`) must match the Maven `groupId`,
and `app` matches the `artifactId`. All source sub-packages live here.

| Sub-package | Layer | Responsibility |
|---|---|---|
| `config/` | Cross-cutting | Spring `@Configuration` / `@Bean` definitions |
| `controller/` | Presentation | `@RestController` classes, `@ControllerAdvice` |
| `service/` | Application | Business-logic interfaces |
| `service/impl/` | Application | Concrete implementations of service interfaces |
| `repository/` | Infrastructure | Spring Data `Repository` interfaces or JPA DAOs |
| `domain/entity/` | Domain | JPA `@Entity` classes |
| `domain/dto/` | Domain | Request/response objects crossing layer boundaries |
| `domain/enums/` | Domain | Type-safe domain enumerations |
| `domain/mapper/` | Domain | MapStruct / ModelMapper converters |
| `exception/` | Cross-cutting | Typed exception hierarchy |
| `security/` | Cross-cutting | Auth filters, JWT providers, `UserDetails` impls |
| `util/` | Cross-cutting | Stateless helpers (no Spring beans where possible) |

### `src/main/resources/`

Environment configuration, database migrations, and static assets.
`application.yml` holds shared defaults; profile-specific files (`-dev`, `-prod`, etc.) contain
only the **delta** from the base — keep them minimal.

### `src/test/`

Mirrors the `main` package hierarchy exactly. Each production class has a corresponding test
class in the same relative package. Integration tests that span multiple layers live in
`test/.../integration/`.

### `.github/workflows/`

All CI/CD automation. Naming convention: `ci.yml` (PR validation), `release.yml` (publish),
`security.yml` (SAST/dependency scan).

### `docs/`

Long-form documentation. ADRs follow the Nygard template and are numbered sequentially
(`0001-`, `0002-`). API docs are generated from OpenAPI annotations and stored here for
offline review.

---

## 4. File Placement Patterns

### Configuration Files

| File | Location | Purpose |
|---|---|---|
| `application.yml` | `src/main/resources/` | Base, shared config |
| `application-{env}.yml` | `src/main/resources/` | Environment overrides |
| `application-test.yml` | `src/test/resources/` | Test overrides (H2, mocks) |
| `logback-spring.xml` | `src/main/resources/` | Logging appenders/levels |
| Spring `@Configuration` | `config/` package | Bean and framework config |
| `pom.xml` | Project root | Maven build descriptor |

### Domain Model Files

| Type | Location |
|---|---|
| JPA entities / aggregates | `domain/entity/` |
| DTOs (request/response) | `domain/dto/` |
| Enumerations | `domain/enums/` |
| MapStruct mappers | `domain/mapper/` |
| Data validation groups | `domain/dto/` (inner interfaces) |

### Business Logic

| Type | Location |
|---|---|
| Service interfaces | `service/` |
| Service implementations | `service/impl/` |
| Business rules (domain-rich model) | `domain/entity/` methods |
| Validators (`@Validator`) | `util/` or dedicated `validator/` sub-package |

### Test Files

| Type | Location |
|---|---|
| Unit tests | `src/test/java/…/<package>/` mirroring production class |
| Spring Slice tests (`@WebMvcTest`, `@DataJpaTest`) | `src/test/java/…/<layer>/` |
| Full integration tests | `src/test/java/…/integration/` |
| Test fixtures / factories | `src/test/java/…/fixtures/` |
| SQL seed data | `src/test/resources/sql/` |

---

## 5. Naming and Organization Conventions

### File Naming

| Category | Convention | Example |
|---|---|---|
| Java classes | `PascalCase` | `UserService.java` |
| Interfaces | `PascalCase` (no `I` prefix) | `UserService.java` |
| Implementations | `<Interface>Impl` suffix | `UserServiceImpl.java` |
| Test classes | `<ClassUnderTest>Test` suffix | `UserServiceTest.java` |
| Integration tests | `<Feature>IntegrationTest` | `UserIntegrationTest.java` |
| DTOs | `<Entity>Request` / `<Entity>Response` | `UserRequest.java` |
| Exceptions | `<Cause>Exception` suffix | `ResourceNotFoundException.java` |
| Constants | `<Domain>Constants` suffix | `SecurityConstants.java` |
| Config classes | `<Concern>Config` suffix | `SecurityConfig.java` |
| Mappers | `<Entity>Mapper` suffix | `UserMapper.java` |
| Migration scripts | `V{n}__{description}.sql` (Flyway) | `V1__init_schema.sql` |

### Folder Naming

- All lowercase, `kebab-case` is acceptable for multi-word directories (e.g., `db/migration`).
- Single-word names preferred within the Java package tree (`config`, `service`, `util`).
- Layer folders are **singular** (`controller`, not `controllers`).

### Package Naming

- Root package: `com.<org>.<app>` — mirrors Maven `groupId.artifactId`.
- Sub-packages reflect technical layer first, domain second:
  `com.example.app.service.user`, `com.example.app.repository.order`.
- Test packages exactly match production packages.

### Organizational Patterns

- **Inward-facing dependencies**: `controller → service interface → repository`; entities
  never import controllers or services.
- **Interface + Impl split**: Every service is backed by an interface in the parent package and
  an implementation in `impl/`. This facilitates mocking and later extraction to a separate module.
- **No circular packages**: Enforce with ArchUnit or Checkstyle.

---

## 6. Navigation and Development Workflow

### Entry Points

| Starting Point | File | Purpose |
|---|---|---|
| Application boot | `Application.java` | `@SpringBootApplication` main class |
| REST surface | `controller/` | All HTTP endpoints |
| Data model | `domain/entity/` | Entity relationship overview |
| Configuration | `src/main/resources/application.yml` | All tuneable properties |
| Database schema | `resources/db/migration/` | Schema history via migrations |
| Build | `pom.xml` | Dependencies, plugins, profiles |

### Adding a New Feature (e.g., `Order`)

1. Create `domain/entity/Order.java` (JPA entity).
2. Add `domain/dto/OrderRequest.java` and `OrderResponse.java`.
3. Create `domain/mapper/OrderMapper.java`.
4. Define `service/OrderService.java` interface.
5. Implement `service/impl/OrderServiceImpl.java`.
6. Create `repository/OrderRepository.java` (Spring Data interface).
7. Add `controller/OrderController.java`.
8. Write `src/test/java/…/service/OrderServiceTest.java`.
9. Write `src/test/java/…/controller/OrderControllerTest.java`.
10. Add a Flyway migration `Vn__add_order_table.sql`.

### Dependency Flow

```
HTTP Request
     │
     ▼
[ Controller ]  ──▶  @Valid DTOs
     │
     ▼
[ Service Interface ]
     │
     ▼
[ ServiceImpl ]  ──▶  Domain logic
     │
     ▼
[ Repository ]  ──▶  JPA / Spring Data
     │
     ▼
[ Entity / Database ]
```

Controllers **must not** directly access repositories.
Services **must not** return JPA entities — always map to DTOs.

---

## 7. Build and Output Organization

### Build Configuration

| File / Location | Purpose |
|---|---|
| `pom.xml` | Maven coordinates, dependencies, plugins, profiles |
| `.github/workflows/ci.yml` | GitHub Actions CI: compile → test → lint → package |
| `scripts/build.sh` | Local full build helper |
| `scripts/run-local.sh` | Start application locally with dev profile |

### Maven Profiles

| Profile ID | Activation | Purpose |
|---|---|---|
| `dev` | `-P dev` or default | H2 in-memory, debug logging |
| `staging` | `-P staging` | Staging DB, reduced logging |
| `prod` | `-P prod` | Production DB, minimal logging, skip integration tests |

### Output Structure

```
target/
├── classes/                  # Compiled production bytecode
├── test-classes/             # Compiled test bytecode
├── surefire-reports/         # Unit test reports (XML + HTML)
├── failsafe-reports/         # Integration test reports
├── jacoco.exec               # Coverage data
├── site/                     # Maven site reports
└── mbb-java-maven-1.0.0.jar  # Executable JAR (Spring Boot fat jar)
```

`target/` is **always** in `.gitignore`.

---

## 8. Java / Maven-Specific Patterns

### Package Hierarchy Design

```
com.example.app
├── (root)            Application.java
├── config            Framework wiring
├── controller        REST handlers
│   └── advice        Exception mappers
├── service           Business interfaces
│   └── impl          Implementations
├── repository        Data access
├── domain
│   ├── entity        Persistent objects
│   ├── dto           Transfer objects
│   ├── enums         Typed constants
│   └── mapper        Conversion logic
├── exception         Error hierarchy
├── security          Auth & authorisation
└── util              Pure helpers
```

### `pom.xml` Internal Organization

Recommended section order within `pom.xml`:

1. `<modelVersion>`, `<groupId>`, `<artifactId>`, `<version>`, `<packaging>`
2. `<parent>` (Spring Boot Starter Parent)
3. `<properties>` — Java version, encoding, dependency versions
4. `<dependencies>` — grouped: **Core**, **Web**, **Data**, **Security**, **Util**, **Test**
5. `<dependencyManagement>` — BOM imports
6. `<build><plugins>` — compiler, Surefire, Failsafe, Jacoco, SpotBugs, Checkstyle
7. `<profiles>` — `dev`, `staging`, `prod`

### Resource Organization

| Resource | Location | Notes |
|---|---|---|
| Base config | `main/resources/application.yml` | YAML preferred over `.properties` |
| Profile configs | `main/resources/application-{profile}.yml` | Only overrides — not full copies |
| DB migrations | `main/resources/db/migration/` | Flyway auto-scanned path |
| i18n bundles | `main/resources/i18n/` | `messages.properties` base |
| Logging | `main/resources/logback-spring.xml` | Profile-aware via `<springProfile>` |
| Test config | `test/resources/application-test.yml` | H2, mock endpoints |
| Test SQL | `test/resources/sql/` | Referenced by `@Sql` annotations |

### Key Maven Plugins (Recommended Baseline)

| Plugin | Purpose |
|---|---|
| `spring-boot-maven-plugin` | Repackage as executable JAR |
| `maven-compiler-plugin` | Pin Java source/target version |
| `maven-surefire-plugin` | Run unit tests (`*Test.java`) |
| `maven-failsafe-plugin` | Run integration tests (`*IT.java`) |
| `jacoco-maven-plugin` | Code coverage; fail if below threshold |
| `spotbugs-maven-plugin` | Static bug analysis |
| `checkstyle-maven-plugin` | Code style enforcement |
| `versions-maven-plugin` | Dependency upgrade checks |
| `maven-enforcer-plugin` | Minimum Maven/Java version gate |

---

## 9. Extension and Evolution

### Adding a New Bounded Context / Module

For **small additions**, add a sub-package under each layer:

```
service/order/OrderService.java
service/order/impl/OrderServiceImpl.java
repository/order/OrderRepository.java
domain/entity/Order.java
```

For **large domains**, extract to a Maven module:

```
mbb-java-maven/
├── core/           # shared domain types, exceptions, utils
├── user-service/   # user bounded context module
├── order-service/  # order bounded context module
└── web-api/        # REST adapter — depends on *-service modules
```

### Scalability Patterns

- Prefer **interface segregation** — split broad service interfaces before the class grows
  beyond ~400 lines.
- Use **Spring `@Profile`** to swap implementations rather than `if/else` chains.
- Introduce `event/` package for internal domain events before wiring Kafka/RabbitMQ.

### Refactoring Patterns

| Smell | Refactoring |
|---|---|
| Fat `ServiceImpl` | Extract sub-services or domain service objects |
| Controllers with logic | Push logic into service layer |
| Entity with validation | Move validation into dedicated `Validator` or `@DomainService` |
| Duplicate mappers | Centralise in `domain/mapper/` using MapStruct |

---

## 10. Structure Templates

### New Feature Checklist

```
src/main/java/com/example/app/
├── domain/entity/<Feature>.java          # JPA entity
├── domain/dto/<Feature>Request.java      # Input DTO (validation annotations)
├── domain/dto/<Feature>Response.java     # Output DTO
├── domain/mapper/<Feature>Mapper.java    # MapStruct interface
├── repository/<Feature>Repository.java   # extends JpaRepository<Feature, Long>
├── service/<Feature>Service.java         # Interface
├── service/impl/<Feature>ServiceImpl.java
└── controller/<Feature>Controller.java   # @RestController

src/main/resources/db/migration/
└── V{n}__add_<feature>_table.sql

src/test/java/com/example/app/
├── service/<Feature>ServiceTest.java
├── controller/<Feature>ControllerTest.java
└── integration/<Feature>IntegrationTest.java
```

### New Service Template (`UserService` example)

```java
// service/UserService.java
package com.example.app.service;

import com.example.app.domain.dto.UserRequest;
import com.example.app.domain.dto.UserResponse;
import java.util.List;

public interface UserService {
    UserResponse create(UserRequest request);
    UserResponse findById(Long id);
    List<UserResponse> findAll();
    UserResponse update(Long id, UserRequest request);
    void delete(Long id);
}

// service/impl/UserServiceImpl.java
@Service
@RequiredArgsConstructor
public class UserServiceImpl implements UserService {
    private final UserRepository userRepository;
    private final UserMapper userMapper;
    // ...
}
```

### New Controller Template

```java
@RestController
@RequestMapping("/api/v1/users")
@RequiredArgsConstructor
@Tag(name = "Users", description = "User management API")
public class UserController {
    private final UserService userService;

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public UserResponse create(@Valid @RequestBody UserRequest request) {
        return userService.create(request);
    }

    @GetMapping("/{id}")
    public UserResponse findById(@PathVariable Long id) {
        return userService.findById(id);
    }
}
```

### Test Template

```java
@ExtendWith(MockitoExtension.class)
class UserServiceTest {
    @Mock UserRepository userRepository;
    @Mock UserMapper userMapper;
    @InjectMocks UserServiceImpl userService;

    @Test
    void create_givenValidRequest_returnsResponse() {
        // arrange
        // act
        // assert
    }
}
```

---

## 11. Structure Enforcement

### Automated Checks

| Tool | Configuration | What It Enforces |
|---|---|---|
| **Checkstyle** | `checkstyle.xml` in project root or `src/main/config/` | Naming conventions, import order, header |
| **ArchUnit** | `src/test/java/…/ArchitectureTest.java` | Layer dependency rules (no controller → repository) |
| **SpotBugs** | `spotbugs.xml` | Common bug patterns |
| **Maven Enforcer** | `pom.xml` `<enforcer>` plugin | Min Java/Maven version, banned dependencies |
| **JaCoCo** | `pom.xml` `<jacoco>` plugin | Coverage threshold (suggest ≥ 80%) |
| **GitHub Actions** | `.github/workflows/ci.yml` | All of the above run on every PR |

### Sample ArchUnit Rule

```java
@AnalyzeClasses(packages = "com.example.app")
public class ArchitectureTest {
    @ArchTest
    static final ArchRule controllers_should_not_access_repositories =
        noClasses().that().resideInAPackage("..controller..")
            .should().dependOnClassesThat()
            .resideInAPackage("..repository..");

    @ArchTest
    static final ArchRule services_should_not_depend_on_controllers =
        noClasses().that().resideInAPackage("..service..")
            .should().dependOnClassesThat()
            .resideInAPackage("..controller..");
}
```

### Documentation Practices

- **ADRs** — record significant architectural decisions under `docs/adr/` using the Nygard
  template. Number sequentially; never delete, only supersede.
- **CHANGELOG.md** — updated per release following [Keep a Changelog](https://keepachangelog.com).
- **README.md** — reflects current build, run, and test instructions.
- **This blueprint** — update whenever a new top-level package or significant structural pattern
  is introduced.

---

## Maintaining This Blueprint

| Trigger | Required Update |
|---|---|
| New top-level package added | Section 2 (visualization) + Section 3 |
| New Maven module extracted | Section 2, Section 9 |
| New CI/CD workflow added | Section 7 |
| Naming convention changed | Section 5 |
| New enforcement tool added | Section 11 |

**Owner**: assigned tech lead or architect for the repository.
**Review cadence**: each sprint review, or immediately after any structural refactoring.
