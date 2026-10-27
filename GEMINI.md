# Development Guidelines for vimmd

This project adheres strictly to **Agentic Orchestration**, **Test-Driven Development (TDD)**, **Modular Programming**, and **Atomic Commits**. All contributors and AI assistants working in this repository must follow these rules.

---

## 1. Orchestration & Subagent Architecture

Because `vimmd` is a large, complex project, the primary assistant operates strictly as an **Orchestrator** to conserve its context window and ensure high-level architectural oversight.

### Delegation Rules
- **Orchestrator Role**: The primary agent plans tasks, tracks milestones, coordinates workflows, and manages overall project state. The orchestrator must not write implementation code directly in the main conversation context.
- **Subagent Coding**: All coding, refactoring, and test authoring must be delegated to dedicated coding subagents (`invoke_subagent`).
- **Context Window Preservation**: Subagents execute isolated, focused coding cycles. Only high-level summaries, verification outcomes, and review sign-offs are returned to the orchestrator.

### Adversarial Code Review Protocol
- **Mandatory 2nd-Agent Review**: Before any code produced by a coding subagent is accepted, used, or committed, it **must** be reviewed by a separate, adversarial code review subagent.
- **Adversarial Posture**: The review agent actively hunts for flaws, including:
  - Missing or weak test assertions (violating TDD rigor).
  - Subtle edge case bugs, off-by-one errors, and boundary condition failures.
  - Architectural leakage, tight coupling, and SRP violations.
  - Unsafe operations, performance bottlenecks, or non-deterministic behaviors.
- **Sign-off Gate**: Implementation code is only merged or committed once the adversarial reviewer explicitly approves the changes. If issues are identified, the implementation must be sent back for revision before acceptance.

---

## 2. Test-Driven Development (TDD)

All functionality and bug fixes must be driven by tests. Do not write production code without a failing test first.

### The Red-Green-Refactor Cycle
1. **RED**: Write a failing unit or integration test that defines the expected behavior, edge case, or bug reproduction.
   - Run the test suite to confirm the test fails for the expected reason.
2. **GREEN**: Write the minimal implementation necessary to make the failing test pass.
   - Avoid implementing unneeded abstractions or speculative features at this stage.
3. **REFACTOR**: Clean up the implementation and tests without changing observable behavior.
   - Improve readability, reduce duplication, and ensure architectural boundaries are respected.
   - Re-run all tests after refactoring to ensure green status.

### Testing Standards
- **Hermetic & Deterministic**: Tests must run without network dependencies, non-deterministic timers, or unmocked external environment side effects.
- **Fast Feedback**: Unit tests must execute quickly. Keep heavy I/O and process orchestration isolated in dedicated integration test suites.
- **Edge Cases & Failure Modes**: Write tests for boundaries, nil/null inputs, empty states, error propagation, and malformed inputs.
- **Bug Fix Protocol**: Every bug report must begin with a reproduction test demonstrating the defect before any code changes are made.

---

## 3. Modular Programming

Code must be composed of small, focused, loosely coupled modules with clear boundaries and well-defined contracts.

### Architectural Principles
- **Single Responsibility Principle (SRP)**: Each module, package, or class must have one reason to change and encapsulate a single piece of domain logic.
- **Explicit Interfaces & Contracts**: Expose clean public APIs. Depend on interfaces/abstractions rather than concrete implementations to ease testability and swapping components.
- **Separation of Concerns**:
  - Keep domain logic, data models, parser/formatting logic, and platform/CLI/UI integration isolated in separate layers/packages.
  - Core domain logic must have zero dependencies on CLI parsers, terminal wrappers, or I/O adapters.
- **Minimizing Shared & Global State**: Avoid global mutable variables, singletons, or implicit state. Pass dependencies explicitly via dependency injection or constructor parameters.
- **Small File Footprint**: Avoid monolithic files ("god files"). Split modules once they take on multiple responsibilities or grow beyond cohesive scope.

---

## 4. Atomic Commits

Git commits must be granular, focused, and self-contained units of work.

### Rules of Atomic Commits
1. **Single Logical Change**: A commit does one thing and one thing only. Do not mix unrelated changes (e.g., refactoring existing code, formatting, and adding a new feature must each be separate commits).
2. **Green Build at Every Commit**: Every commit must be functionally complete, compile cleanly, and pass all existing and new tests. Broken intermediate states should never be committed.
3. **Separate Behavior from Refactoring**:
   - First commit: Refactor code to prepare for a change (tests stay green).
   - Second commit: Add the new behavior or feature (with tests).
4. **No "WIP" or Catch-All Commits**: Avoid mega-commits like `fix stuff`, `wip`, or `misc updates`. If a feature is large, break it down into sequential, reviewable atomic steps.

### Commit Message Convention
Follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>(<optional scope>): <short description in imperative mood>

[optional body explaining motivation and context]

[optional footer(s)]
```

#### Types:
- `test`: Adding or correcting tests (no production code changes).
- `feat`: Adding a new user-facing or public capability.
- `fix`: Fixing a bug.
- `refactor`: Code changes that neither fix a bug nor add a feature.
- `chore`: Build scripts, tooling, dependencies, or configuration changes.
- `docs`: Documentation updates only.
- `perf`: Code changes improving performance.

#### Examples:
- `test(parser): add test cases for nested markdown task lists`
- `feat(parser): support nested task list items`
- `refactor(render): extract color theme resolution to theme provider`
- `fix(cursor): prevent out-of-bounds column navigation on blank lines`

---

## 5. Definition of Done (DoD) Checklist

Before submitting code or closing a task, verify:
- [ ] Task executed via dedicated coding subagent to protect orchestrator context.
- [ ] Tests written first and verified failing before implementation (TDD).
- [ ] Minimal implementation made all tests pass.
- [ ] Code refactored for clarity and modularity.
- [ ] Adversarial 2nd-agent code review conducted and passed with explicit sign-off.
- [ ] Full test suite and linters pass cleanly.
- [ ] Changes broken down into atomic, well-described commits.
