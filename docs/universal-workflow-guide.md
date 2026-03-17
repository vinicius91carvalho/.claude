# Universal Workflow Guide

This workflow system is **language-agnostic by design**. It auto-detects your project's language(s) and adapts its behavior — TDD enforcement, auto-formatting, type checking, dependency management, and gitignore generation all work without configuration for supported languages.

## Supported Languages (out of the box)

| Language | Type Checker | Formatter | TDD Patterns | Dependency Mgmt |
|----------|-------------|-----------|--------------|-----------------|
| TypeScript | tsgo / tsc | Biome, ESLint, Prettier | `*.test.ts`, `*.spec.ts`, `__tests__/` | pnpm / yarn / npm / bun |
| JavaScript | — | Biome, ESLint, Prettier | `*.test.js`, `*.spec.js`, `__tests__/` | pnpm / yarn / npm / bun |
| Python | pyright, mypy | ruff, black, autopep8 | `test_*.py`, `*_test.py`, `tests/` | poetry, uv, pip, pipenv |
| Go | go vet | goimports, gofmt | `*_test.go` | go mod download |
| Rust | cargo check | rustfmt | `tests/*.rs`, inline `#[cfg(test)]` | cargo fetch |
| Ruby | — | rubocop | `*_spec.rb`, `*_test.rb`, `spec/`, `test/` | bundle install |
| Java | gradle/maven compile | google-java-format, spotless | `*Test.java`, `src/test/java/` | gradle / maven |
| Kotlin | gradle compileKotlin | ktlint | `*Test.kt`, `src/test/kotlin/` | gradle |
| Elixir | — | mix format | `*_test.exs`, `test/` | mix deps.get |
| Swift | swift build | swift-format, swiftformat | `*Tests.swift`, `Tests/` | swift package resolve |
| Dart | dart analyze | dart format | `*_test.dart`, `test/` | dart pub get |
| C# | dotnet build | dotnet format | `*Tests.cs`, `*.Tests/` | dotnet restore |
| Scala | sbt compile | scalafmt | `*Spec.scala`, `*Test.scala` | sbt update |
| C / C++ | — | clang-format | `*_test.c`, `test/`, `tests/` | — |
| Haskell | stack build / cabal | ormolu, fourmolu | `*Spec.hs`, `*Test.hs` | stack setup / cabal update |
| Zig | zig build | zig fmt | inline `test "name" {}`, `test/` | — |

## How Detection Works

The system uses **marker files** to detect your project's language(s). No configuration required.

### Marker Files → Language Detection

| Marker File | Detected Language |
|------------|-------------------|
| `tsconfig.json` | TypeScript |
| `package.json` (no tsconfig) | JavaScript |
| `deno.json` / `deno.jsonc` | Deno |
| `go.mod` | Go |
| `Cargo.toml` | Rust |
| `pyproject.toml` / `setup.py` / `requirements.txt` / `Pipfile` | Python |
| `Gemfile` | Ruby |
| `build.gradle` / `build.gradle.kts` / `pom.xml` | Java |
| `build.gradle.kts` + `src/main/kotlin/` | Kotlin |
| `mix.exs` | Elixir |
| `Package.swift` | Swift |
| `CMakeLists.txt` / `Makefile` / `meson.build` | C / C++ |
| `build.zig` | Zig |
| `pubspec.yaml` | Dart |
| `*.csproj` / `*.sln` | C# |
| `build.sbt` | Scala |
| `stack.yaml` / `*.cabal` | Haskell |

### Multi-Language Projects

Projects can have **multiple languages** (e.g., a TypeScript frontend + Go backend). The system detects all of them. The hooks act per-file — a `.go` file triggers Go-specific behavior, a `.ts` file triggers TypeScript-specific behavior.

## Architecture

All language-specific logic is centralized in one file:

```
~/.claude/hooks/lib/detect-project.sh    ← ALL language detection lives here
~/.claude/hooks/end-of-turn-typecheck.sh ← Stop hook: type checking (sources lib)
~/.claude/hooks/post-edit-quality.sh     ← PostToolUse: auto-formatting (sources lib)
~/.claude/hooks/check-test-exists.sh     ← PreToolUse: TDD enforcement (sources lib)
~/.claude/hooks/check-invariants.sh      ← PostToolUse: invariant verification (sources lib)
~/.claude/hooks/worktree-preflight.sh    ← Sprint prep: git + deps (sources lib)
~/.claude/hooks/block-dangerous.sh       ← PreToolUse: safety gates
~/.claude/hooks/proot-preflight.sh       ← PreToolUse: proot environment detection
```

### Hook → Library Function Mapping

| Hook | Library Functions Used |
|------|----------------------|
| `end-of-turn-typecheck.sh` | `detect_project_langs`, `detect_typechecker`, `code_extensions_for_lang`, `detect_pkg_manager` |
| `post-edit-quality.sh` | `is_code_file`, `is_generated_path`, `detect_formatter`, `detect_pkg_manager` |
| `check-test-exists.sh` | `is_code_file`, `is_test_file`, `is_config_file`, `is_generated_path`, `is_entry_point`, `lang_for_extension`, `has_test_infra`, `find_test_candidates` |
| `check-invariants.sh` | `is_code_file`, `is_generated_path` |
| `worktree-preflight.sh` | `detect_project_langs`, `detect_pkg_manager`, `detect_dep_install_cmd` |

## Adding a New Language

To add support for a new language (e.g., Lua, PHP, Nim), edit **one file**: `~/.claude/hooks/lib/detect-project.sh`.

### Step-by-step

#### 1. File Extension Mapping

In `lang_for_extension()`, add your extension → language mapping:

```bash
lang_for_extension() {
  case "$1" in
    # ... existing entries ...
    nim)          echo "nim" ;;      # ← ADD THIS
    *)            echo "" ;;
  esac
}
```

#### 2. Project Detection

In `detect_project_langs()`, add marker file detection:

```bash
detect_project_langs() {
  # ... existing entries ...

  # Nim
  [ -f "$dir/nim.cfg" ] || [ -f "$dir/*.nimble" ] && PROJECT_LANGS+=("nim")
}
```

#### 3. Test File Patterns

In `is_test_file()`, add test file naming conventions:

```bash
is_test_file() {
  # ... existing entries ...
  nim)
    case "$basename" in
      test_*|t_*) return 0 ;;
    esac
    case "$filepath" in
      */tests/*|*/test/*) return 0 ;;
    esac
    ;;
}
```

#### 4. Test Candidates

In `find_test_candidates()`, add where tests might live:

```bash
find_test_candidates() {
  # ... existing entries ...
  nim)
    TEST_CANDIDATES+=(
      "$project_dir/tests/test_${filename}.nim"
      "$project_dir/tests/t_${filename}.nim"
      "$dirname/test_${filename}.nim"
    )
    ;;
}
```

#### 5. Test Infrastructure Detection

In `has_test_infra()`, add how to detect if tests are set up:

```bash
has_test_infra() {
  # ... existing entries ...
  nim|"")
    [ -d "$dir/tests" ] && return 0
    [ -n "$lang" ] && return 1
    ;;&
}
```

#### 6. Formatter Detection

In `detect_formatter()`, add formatter/linter support:

```bash
detect_formatter() {
  # ... existing entries ...
  nim)
    if command -v nimpretty &>/dev/null; then
      FORMATTER_CMD="nimpretty"
    fi
    ;;
}
```

#### 7. Type Checker Detection

In `detect_typechecker()`, add compile/check command:

```bash
detect_typechecker() {
  # ... existing entries ...
  nim)
    if command -v nim &>/dev/null; then
      TYPECHECKER_NAME="nim check"
      TYPECHECKER_CMD="nim check"
    fi
    ;;
}
```

#### 8. Dependency Management

In `detect_dep_install_cmd()`, add dependency install command:

```bash
detect_dep_install_cmd() {
  # ... existing entries ...
  nim)
    if command -v nimble &>/dev/null; then
      DEP_INSTALL_CMD="nimble install -d"
    fi
    DEP_LANG="nim"
    [ -n "$DEP_INSTALL_CMD" ] && return 0
    ;;
}
```

#### 9. Generated Directories

In `is_generated_path()`, add build output directories:

```bash
is_generated_path() {
  # ... existing entries ...
  # Nim
  */nimcache/*) return 0 ;;
}
```

#### 10. Config Files (optional)

In `is_config_file()`, add config file names:

```bash
is_config_file() {
  # ... existing entries ...
  *.nimble|nim.cfg) return 0 ;;
}
```

#### 11. Entry Points (optional)

In `is_entry_point()`, add main/entry file names:

```bash
is_entry_point() {
  # ... existing entries ...
  main.nim) return 0 ;;
}
```

### After Adding

1. **Test the hook chain**: Edit a file of the new language and verify:
   - `check-test-exists.sh` enforces TDD (blocks without test file)
   - `post-edit-quality.sh` runs the formatter (if available)
   - `end-of-turn-typecheck.sh` runs the type checker (at end of turn)
   - `check-invariants.sh` recognizes the file as code

2. **Test worktree-preflight**: Run it in a project directory and verify dependency detection:
   ```bash
   bash ~/.claude/hooks/worktree-preflight.sh
   ```

3. **Optionally add to worktree-preflight.sh**: If the language needs specific `.gitignore` entries or dependency management in the worktree bootstrap, add a case block there.

## Project-Level Configuration

For project-specific settings that override defaults, use the project's `CLAUDE.md` file:

```markdown
## Execution Config

- **Package manager:** pnpm
- **Test command:** pnpm vitest run
- **Lint command:** pnpm biome check
- **Build command:** pnpm build
- **Type check command:** pnpm tsc --noEmit
```

Skills (`/plan-build-test`, `/ship-test-ensure`) read from `## Execution Config`. The hooks auto-detect without configuration — project CLAUDE.md is for overrides and skill-level commands.

## Settings.json Environment Variables

The `settings.json` env section contains Node.js-specific variables:

```json
{
  "env": {
    "NODE_OPTIONS": "--max-old-space-size=2048",
    "CHOKIDAR_USEPOLLING": "true",
    "WATCHPACK_POLLING": "true"
  }
}
```

These are harmless for non-Node.js projects (they're only read by Node.js processes). If you're never working on Node.js projects, you can remove them.

To add environment variables for other languages, add them here:

```json
{
  "env": {
    "RUST_BACKTRACE": "1",
    "PYTHONDONTWRITEBYTECODE": "1",
    "GOFLAGS": "-count=1"
  }
}
```

## proot-distro ARM64 Considerations

Some language toolchains have known issues in proot-distro ARM64:

| Language | Issue | Workaround |
|----------|-------|------------|
| Node.js | Native modules fail (@parcel/watcher, sharp, turbo) | Use JS fallbacks, `--ignore-scripts` |
| Rust | Long compile times, may OOM | Use `cargo check` instead of `cargo build`, set `codegen-units = 1` |
| Go | `/proc/self/exe` → `/.l2s/` translation | Copy required resource files to `/.l2s/` |
| Python | No known issues | Works well in proot |
| Java | JVM startup is slow | Use Gradle daemon, increase memory |
| C/C++ | Native compilation works | No issues known |

## Workflow Components That Are 100% Language-Agnostic

These require zero changes regardless of language:

- **PRD system** — Plan/Sprint decomposition
- **INVARIANTS.md** — Cross-module contracts (verify commands are shell commands)
- **Contract-First pattern** — Intent → Mirror → Receipt
- **Judgment protocols** — Confidence levels, risk categories
- **Anti-Premature Completion** — Verification checklist
- **Session Learnings** — Error/pattern capture
- **Compound Engineering** — Post-task learning loop
- **Verification Pattern** — Prose spec + executable tests + iteration loops
- **Git workflow** — Branching, commits, PRs
- **Agent architecture** — Orchestrator, sprint-executor, code-reviewer
