#!/usr/bin/env bash
# Shared project/language detection utilities for Claude Code hooks.
#
# Source this file from any hook:
#   HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$HOOK_DIR/lib/detect-project.sh" 2>/dev/null || source ~/.claude/hooks/lib/detect-project.sh
#
# === EXTENDING FOR A NEW LANGUAGE ===
# To add support for a new language/ecosystem:
#   1. Add file extensions to lang_for_extension()
#   2. Add marker file detection to detect_project_langs()
#   3. Add test file patterns to is_test_file() and find_test_candidates()
#   4. Add test infrastructure markers to has_test_infra()
#   5. Add formatter/linter detection to detect_formatter()
#   6. Add type checker detection to detect_typechecker()
#   7. Add dependency install logic to detect_dep_install_cmd()
#   8. Add generated/build directory patterns to is_generated_path()
#   9. Add config/setup file patterns to is_config_file()
#  10. Add entry point patterns to is_entry_point()
#
# Each function documents its output variables. All functions are idempotent.

# ─── FILE CLASSIFICATION ───────────────────────────────────────────────

# Maps a file extension to a language identifier.
# Usage: LANG=$(lang_for_extension "ts")
lang_for_extension() {
  case "$1" in
    ts|tsx)       echo "typescript" ;;
    js|jsx|mjs|cjs) echo "javascript" ;;
    py|pyi)       echo "python" ;;
    go)           echo "go" ;;
    rs)           echo "rust" ;;
    rb)           echo "ruby" ;;
    java)         echo "java" ;;
    kt|kts)       echo "kotlin" ;;
    scala|sc)     echo "scala" ;;
    ex|exs)       echo "elixir" ;;
    swift)        echo "swift" ;;
    c|h)          echo "c" ;;
    cpp|cc|cxx|hpp|hxx) echo "cpp" ;;
    cs)           echo "csharp" ;;
    php)          echo "php" ;;
    zig)          echo "zig" ;;
    lua)          echo "lua" ;;
    hs)           echo "haskell" ;;
    dart)         echo "dart" ;;
    *)            echo "" ;;
  esac
}

# Returns 0 if the file extension is a known code file.
# Usage: is_code_file "src/main.rs" && echo "yes"
is_code_file() {
  local ext="${1##*.}"
  local lang
  lang=$(lang_for_extension "$ext")
  [ -n "$lang" ]
}

# Returns 0 if the path is inside a generated, vendor, or build directory.
# Usage: is_generated_path "/project/node_modules/foo.js" && echo "skip"
is_generated_path() {
  # Normalize: ensure path starts with / for consistent matching
  local p="/$1"
  case "$p" in
    # Universal
    */vendor/*|*/.git/*) return 0 ;;
    # Node.js / JavaScript / TypeScript
    */node_modules/*|*/dist/*|*/build/*|*/.next/*|*/coverage/*) return 0 ;;
    */.turbo/*|*/__generated__/*|*/.generated/*|*/generated/*) return 0 ;;
    */.cache/*|*/.output/*|*/.nuxt/*|*/.svelte-kit/*|*/.vercel/*) return 0 ;;
    */.graphql/*|*/graphql/generated/*|*/.prisma/*|*/prisma/generated/*) return 0 ;;
    */.storybook/static/*|*/out/*|*/.parcel-cache/*|*/.turbopack/*) return 0 ;;
    # Python
    */__pycache__/*|*/.mypy_cache/*|*/.pytest_cache/*|*/.ruff_cache/*) return 0 ;;
    */*.egg-info/*|*/.eggs/*|*/.tox/*|*/.nox/*|*/.venv/*|*/venv/*) return 0 ;;
    */site-packages/*) return 0 ;;
    # Rust
    */target/debug/*|*/target/release/*|*/target/doc/*) return 0 ;;
    # Go
    */go/pkg/*) return 0 ;;
    # Java / Kotlin / Scala
    */target/classes/*|*/build/classes/*|*/build/libs/*) return 0 ;;
    */.gradle/*) return 0 ;;
    # C / C++
    */cmake-build-*/*) return 0 ;;
    # Dart / Flutter
    */.dart_tool/*|*/build/flutter_assets/*) return 0 ;;
    # Elixir
    */_build/*|*/deps/*) return 0 ;;
    # .NET / C#
    */bin/Debug/*|*/bin/Release/*|*/obj/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Returns 0 if the file is a config/setup/infrastructure file (not business logic).
# Usage: is_config_file "vite.config.ts" && echo "skip TDD"
is_config_file() {
  local filepath="$1"
  local basename
  basename=$(basename "$filepath")

  case "$filepath" in
    # Universal config patterns
    *.config.*|*.setup.*|*.conf|*.cfg) return 0 ;;
    */migrations/*|*/seeds/*|*/fixtures/*|*/scripts/*|*/bin/*) return 0 ;;
    */docs/*|*/documentation/*) return 0 ;;
    *Dockerfile*|*docker-compose*|*.dockerignore) return 0 ;;
    *Makefile|*.mk) return 0 ;;
    # Non-code files
    *.md|*.txt|*.rst|*.json|*.yaml|*.yml|*.toml|*.env*) return 0 ;;
    *.css|*.scss|*.less|*.html|*.xml|*.svg) return 0 ;;
  esac

  case "$basename" in
    # Node.js / TypeScript
    vite.config*|next.config*|tailwind.config*|postcss.config*) return 0 ;;
    tsconfig*|biome.json*|eslint.config*|.eslintrc*|.prettierrc*) return 0 ;;
    package.json|pnpm-lock.yaml|yarn.lock|package-lock.json) return 0 ;;
    # Python
    conftest.py|setup.py|setup.cfg|pyproject.toml|manage.py) return 0 ;;
    wsgi.py|asgi.py|alembic.ini|noxfile.py|tox.ini) return 0 ;;
    # Rust
    Cargo.toml|Cargo.lock|build.rs|clippy.toml|rustfmt.toml) return 0 ;;
    # Go
    go.mod|go.sum) return 0 ;;
    # Ruby
    Gemfile|Gemfile.lock|Rakefile|.rubocop.yml) return 0 ;;
    # Java / Kotlin / Scala
    build.gradle|build.gradle.kts|settings.gradle|settings.gradle.kts|pom.xml) return 0 ;;
    build.sbt) return 0 ;;
    # Elixir
    mix.exs|mix.lock) return 0 ;;
    # C / C++
    CMakeLists.txt|*.cmake) return 0 ;;
    # Dart
    pubspec.yaml|pubspec.lock|analysis_options.yaml) return 0 ;;
    *) return 1 ;;
  esac
}

# Returns 0 if the file is a language entry point (main, index, app, __init__).
# Usage: is_entry_point "src/index.ts" && echo "skip TDD"
is_entry_point() {
  local basename
  basename=$(basename "$1")

  case "$basename" in
    # Node.js / TypeScript
    index.ts|index.tsx|index.js|index.jsx) return 0 ;;
    main.ts|main.tsx|main.js|main.jsx) return 0 ;;
    app.ts|app.tsx|app.js|app.jsx) return 0 ;;
    # Python
    __init__.py|__main__.py) return 0 ;;
    # Rust
    main.rs|lib.rs|mod.rs) return 0 ;;
    # Go
    main.go) return 0 ;;
    # Java / Kotlin
    Main.java|Application.java|App.java) return 0 ;;
    Main.kt|Application.kt|App.kt) return 0 ;;
    # Elixir
    application.ex) return 0 ;;
    # Dart
    main.dart) return 0 ;;
    # C / C++
    main.c|main.cpp|main.cc) return 0 ;;
    *) return 1 ;;
  esac
}

# ─── PROJECT DETECTION ─────────────────────────────────────────────────

# Cache directory and TTL for language detection results.
_DETECT_CACHE_DIR="${HOME}/.claude/hooks/logs/.cache"
_DETECT_CACHE_TTL=300  # 5 minutes

# Detects all languages present in a project directory.
# Sets: PROJECT_LANGS (array), PRIMARY_LANG (string)
# Caches result to ~/.claude/hooks/logs/.cache/langs_{project_hash} for 5 minutes.
# Usage: detect_project_langs "/path/to/project"
detect_project_langs() {
  local dir="$1"
  PROJECT_LANGS=()
  PRIMARY_LANG=""

  # === SESSION-LEVEL LANGUAGE DETECTION CACHE ===
  # Hash the project directory path for a stable, short cache key.
  local _phash
  _phash=$(printf '%s' "$dir" | cksum | cut -d' ' -f1)
  local _cache_file="${_DETECT_CACHE_DIR}/langs_${_phash}"

  # Ensure cache dir exists (silently)
  mkdir -p "$_DETECT_CACHE_DIR" 2>/dev/null || true

  # Check if cached result exists and is within TTL.
  if [ -f "$_cache_file" ]; then
    local _now _mtime _age
    _now=$(date +%s)
    _mtime=$(stat -c %Y "$_cache_file" 2>/dev/null || echo 0)
    _age=$(( _now - _mtime ))
    if [ "$_age" -lt "$_DETECT_CACHE_TTL" ]; then
      # Cache hit — read the stored languages
      local _cached_line
      _cached_line=$(cat "$_cache_file" 2>/dev/null || true)
      if [ -n "$_cached_line" ]; then
        # Restore array from newline-separated values
        IFS=$'\n' read -r -a PROJECT_LANGS <<< "$_cached_line" 2>/dev/null || true
        if [ ${#PROJECT_LANGS[@]} -gt 0 ]; then
          PRIMARY_LANG="${PROJECT_LANGS[0]}"
          return
        fi
      fi
    fi
  fi

  # Cache miss or expired — detect normally below

  # TypeScript (check before JS — TS projects also have package.json)
  [ -f "$dir/tsconfig.json" ] && PROJECT_LANGS+=("typescript")

  # JavaScript / Node.js (only if not already detected as TypeScript)
  if [ -f "$dir/package.json" ] && [[ ! " ${PROJECT_LANGS[*]:-} " =~ " typescript " ]]; then
    PROJECT_LANGS+=("javascript")
  fi

  # Deno (separate from Node.js)
  [ -f "$dir/deno.json" ] || [ -f "$dir/deno.jsonc" ] && PROJECT_LANGS+=("deno")

  # Go
  [ -f "$dir/go.mod" ] && PROJECT_LANGS+=("go")

  # Rust
  [ -f "$dir/Cargo.toml" ] && PROJECT_LANGS+=("rust")

  # Python
  if [ -f "$dir/pyproject.toml" ] || [ -f "$dir/setup.py" ] || \
     [ -f "$dir/setup.cfg" ] || [ -f "$dir/requirements.txt" ] || \
     [ -f "$dir/Pipfile" ]; then
    PROJECT_LANGS+=("python")
  fi

  # Ruby
  [ -f "$dir/Gemfile" ] && PROJECT_LANGS+=("ruby")

  # Java
  if [ -f "$dir/build.gradle" ] || [ -f "$dir/build.gradle.kts" ] || \
     [ -f "$dir/pom.xml" ]; then
    PROJECT_LANGS+=("java")
  fi

  # Kotlin (separate from Java if it has specific Kotlin markers)
  if [ -f "$dir/build.gradle.kts" ] && [ -d "$dir/src/main/kotlin" ]; then
    PROJECT_LANGS+=("kotlin")
  fi

  # Elixir
  [ -f "$dir/mix.exs" ] && PROJECT_LANGS+=("elixir")

  # Swift
  [ -f "$dir/Package.swift" ] && PROJECT_LANGS+=("swift")

  # C / C++
  if [ -f "$dir/CMakeLists.txt" ] || [ -f "$dir/Makefile" ] || \
     [ -f "$dir/meson.build" ]; then
    PROJECT_LANGS+=("c_cpp")
  fi

  # Zig
  [ -f "$dir/build.zig" ] && PROJECT_LANGS+=("zig")

  # Dart / Flutter
  [ -f "$dir/pubspec.yaml" ] && PROJECT_LANGS+=("dart")

  # C# / .NET
  if ls "$dir"/*.csproj 1>/dev/null 2>&1 || ls "$dir"/*.sln 1>/dev/null 2>&1; then
    PROJECT_LANGS+=("csharp")
  fi

  # Scala
  [ -f "$dir/build.sbt" ] && PROJECT_LANGS+=("scala")

  # Haskell
  if [ -f "$dir/stack.yaml" ] || [ -f "$dir/cabal.project" ] || \
     ls "$dir"/*.cabal 1>/dev/null 2>&1; then
    PROJECT_LANGS+=("haskell")
  fi

  # Primary language = first detected
  if [ ${#PROJECT_LANGS[@]} -gt 0 ]; then
    PRIMARY_LANG="${PROJECT_LANGS[0]}"
  fi

  # Write detection result to cache (newline-separated language list)
  if [ ${#PROJECT_LANGS[@]} -gt 0 ]; then
    printf '%s\n' "${PROJECT_LANGS[@]}" > "$_cache_file" 2>/dev/null || true
  else
    # Cache empty result too, to avoid repeated detection on empty projects
    printf '' > "$_cache_file" 2>/dev/null || true
  fi
}

# Detects the package manager for Node.js projects.
# Sets: PKG_MGR (string: pnpm|bun|yarn|npx)
# Usage: detect_pkg_manager "/path/to/project"
detect_pkg_manager() {
  local dir="$1"
  PKG_MGR=""

  if [ -f "$dir/pnpm-lock.yaml" ] || [ -f "$dir/pnpm-workspace.yaml" ]; then
    PKG_MGR="pnpm"
  elif [ -f "$dir/bun.lockb" ] || [ -f "$dir/bun.lock" ]; then
    PKG_MGR="bun"
  elif [ -f "$dir/yarn.lock" ]; then
    PKG_MGR="yarn"
  elif [ -f "$dir/package-lock.json" ]; then
    PKG_MGR="npx"
  elif [ -f "$dir/package.json" ]; then
    # No lockfile — default to pnpm if available, else npm
    if command -v pnpm &>/dev/null; then
      PKG_MGR="pnpm"
    else
      PKG_MGR="npx"
    fi
  fi
}

# ─── TEST FILE DETECTION ──────────────────────────────────────────────

# Returns 0 if the file is a test/spec file based on language conventions.
# Usage: is_test_file "src/foo.test.ts" && echo "this is a test"
is_test_file() {
  local filepath="$1"
  local basename
  basename=$(basename "$filepath")
  local ext="${basename##*.}"
  local lang
  lang=$(lang_for_extension "$ext")

  case "$lang" in
    typescript|javascript)
      case "$basename" in
        *.test.*|*.spec.*) return 0 ;;
      esac
      case "$filepath" in
        */__tests__/*|*/tests/*|*/test/*) return 0 ;;
        __tests__/*|tests/*|test/*) return 0 ;;
      esac
      ;;
    python)
      case "$basename" in
        test_*|*_test.py) return 0 ;;
      esac
      case "$filepath" in
        */tests/*|*/test/*|tests/*|test/*) return 0 ;;
      esac
      ;;
    go)
      case "$basename" in
        *_test.go) return 0 ;;
      esac
      ;;
    rust)
      # Rust integration tests live in tests/ directory
      case "$filepath" in
        tests/*.rs|*/tests/*.rs) return 0 ;;
        tests/*/*.rs|*/tests/*/*.rs) return 0 ;;
      esac
      # Rust unit tests are inline (#[cfg(test)]) — can't detect from filename
      ;;
    ruby)
      case "$basename" in
        *_spec.rb|*_test.rb|test_*.rb) return 0 ;;
      esac
      case "$filepath" in
        */spec/*|*/test/*|spec/*|test/*) return 0 ;;
      esac
      ;;
    java|kotlin)
      case "$basename" in
        *Test.java|*Tests.java|*Spec.java) return 0 ;;
        *Test.kt|*Tests.kt|*Spec.kt) return 0 ;;
      esac
      case "$filepath" in
        */test/*|*/tests/*|test/*|tests/*) return 0 ;;
      esac
      ;;
    elixir)
      case "$basename" in
        *_test.exs) return 0 ;;
      esac
      case "$filepath" in
        */test/*|test/*) return 0 ;;
      esac
      ;;
    swift)
      case "$basename" in
        *Tests.swift|*Test.swift) return 0 ;;
      esac
      case "$filepath" in
        */Tests/*|Tests/*) return 0 ;;
      esac
      ;;
    dart)
      case "$filepath" in
        */test/*|test/*|*_test.dart) return 0 ;;
      esac
      ;;
    csharp)
      case "$basename" in
        *Tests.cs|*Test.cs) return 0 ;;
      esac
      case "$filepath" in
        *.Tests/*|*.Test/*|*/test/*|*/tests/*|test/*|tests/*) return 0 ;;
      esac
      ;;
    c|cpp)
      case "$filepath" in
        */test/*|*/tests/*|test/*|tests/*|*_test.c|*_test.cpp) return 0 ;;
      esac
      ;;
    scala)
      case "$basename" in
        *Spec.scala|*Test.scala|*Suite.scala) return 0 ;;
      esac
      case "$filepath" in
        */test/*|test/*) return 0 ;;
      esac
      ;;
    zig)
      # Zig uses inline tests (test "name" { ... }) — can't detect from filename
      case "$filepath" in
        */test/*|*/tests/*|test/*|tests/*) return 0 ;;
      esac
      ;;
    haskell)
      case "$basename" in
        *Spec.hs|*Test.hs) return 0 ;;
      esac
      case "$filepath" in
        */test/*|*/tests/*|test/*|tests/*) return 0 ;;
      esac
      ;;
  esac
  return 1
}

# Finds possible test file locations for a source file.
# Sets: TEST_CANDIDATES (array of absolute paths)
# Usage: find_test_candidates "/project/src/foo.ts" "/project"
find_test_candidates() {
  local filepath="$1"
  local project_dir="$2"
  local dirname
  dirname=$(dirname "$filepath")
  local basename
  basename=$(basename "$filepath")
  local filename="${basename%.*}"
  local ext="${basename##*.}"
  local lang
  lang=$(lang_for_extension "$ext")
  local rel_path="${filepath#$project_dir/}"
  local rel_dir
  rel_dir=$(dirname "$rel_path")

  TEST_CANDIDATES=()

  case "$lang" in
    typescript|javascript)
      # Same directory: foo.test.ts, foo.spec.ts
      TEST_CANDIDATES+=(
        "$dirname/${filename}.test.${ext}"
        "$dirname/${filename}.spec.${ext}"
      )
      # Cross-extension: .ts file might have .tsx test and vice versa
      if [ "$ext" = "tsx" ] || [ "$ext" = "ts" ]; then
        TEST_CANDIDATES+=(
          "$dirname/${filename}.test.ts"
          "$dirname/${filename}.test.tsx"
          "$dirname/${filename}.spec.ts"
          "$dirname/${filename}.spec.tsx"
        )
      fi
      # __tests__ directory (same level and parent)
      TEST_CANDIDATES+=(
        "$dirname/__tests__/${filename}.test.${ext}"
        "$dirname/__tests__/${filename}.spec.${ext}"
        "$(dirname "$dirname")/__tests__/${filename}.test.${ext}"
        "$(dirname "$dirname")/__tests__/${filename}.spec.${ext}"
      )
      # Project-level tests/ directory
      TEST_CANDIDATES+=(
        "$project_dir/tests/${rel_dir}/${filename}.test.${ext}"
        "$project_dir/test/${rel_dir}/${filename}.test.${ext}"
      )
      ;;
    python)
      # Same directory: test_foo.py, foo_test.py
      TEST_CANDIDATES+=(
        "$dirname/test_${filename}.py"
        "$dirname/${filename}_test.py"
      )
      # Project-level tests/ directory
      TEST_CANDIDATES+=(
        "$project_dir/tests/test_${filename}.py"
        "$project_dir/tests/${rel_dir}/test_${filename}.py"
        "$project_dir/tests/unit/test_${filename}.py"
        "$project_dir/tests/integration/test_${filename}.py"
      )
      ;;
    go)
      # Go: test file is always in the same directory, same package
      TEST_CANDIDATES+=("$dirname/${filename}_test.go")
      ;;
    rust)
      # Rust integration tests in tests/ directory
      TEST_CANDIDATES+=(
        "$project_dir/tests/${filename}.rs"
        "$project_dir/tests/test_${filename}.rs"
      )
      # Rust also uses inline tests (#[cfg(test)] mod tests { ... })
      # For the TDD hook, we check if the source file itself has inline tests
      # This is handled separately in check-test-exists.sh
      ;;
    ruby)
      # spec/ directory (RSpec convention)
      TEST_CANDIDATES+=(
        "$dirname/${filename}_spec.rb"
        "$project_dir/spec/${rel_dir}/${filename}_spec.rb"
        "$project_dir/spec/unit/${filename}_spec.rb"
      )
      # test/ directory (Minitest convention)
      TEST_CANDIDATES+=(
        "$dirname/${filename}_test.rb"
        "$dirname/test_${filename}.rb"
        "$project_dir/test/${rel_dir}/${filename}_test.rb"
        "$project_dir/test/${rel_dir}/test_${filename}.rb"
      )
      ;;
    java)
      # Maven/Gradle convention: src/test/java mirrors src/main/java
      local test_path
      test_path=$(echo "$filepath" | sed 's|/src/main/java/|/src/test/java/|' | sed "s|${filename}.java|${filename}Test.java|")
      TEST_CANDIDATES+=("$test_path")
      test_path=$(echo "$filepath" | sed 's|/src/main/java/|/src/test/java/|' | sed "s|${filename}.java|${filename}Tests.java|")
      TEST_CANDIDATES+=("$test_path")
      # Same directory fallback
      TEST_CANDIDATES+=("$dirname/${filename}Test.java")
      ;;
    kotlin)
      # Same as Java convention
      local test_path
      test_path=$(echo "$filepath" | sed 's|/src/main/kotlin/|/src/test/kotlin/|' | sed "s|${filename}.kt|${filename}Test.kt|")
      TEST_CANDIDATES+=("$test_path")
      TEST_CANDIDATES+=("$dirname/${filename}Test.kt")
      ;;
    elixir)
      # Elixir: test/ mirrors lib/
      local test_path
      test_path=$(echo "$filepath" | sed 's|/lib/|/test/|' | sed "s|${filename}.ex|${filename}_test.exs|")
      TEST_CANDIDATES+=("$test_path")
      TEST_CANDIDATES+=("$project_dir/test/${filename}_test.exs")
      ;;
    swift)
      # Swift Package Manager: Tests/ mirrors Sources/
      local test_path
      test_path=$(echo "$filepath" | sed 's|/Sources/|/Tests/|' | sed "s|${filename}.swift|${filename}Tests.swift|")
      TEST_CANDIDATES+=("$test_path")
      TEST_CANDIDATES+=("$dirname/${filename}Tests.swift")
      ;;
    dart)
      # Dart: test/ mirrors lib/
      local test_path
      test_path=$(echo "$filepath" | sed 's|/lib/|/test/|' | sed "s|${filename}.dart|${filename}_test.dart|")
      TEST_CANDIDATES+=("$test_path")
      TEST_CANDIDATES+=("$project_dir/test/${filename}_test.dart")
      ;;
    csharp)
      # .NET: *.Tests project mirrors source project
      TEST_CANDIDATES+=(
        "$dirname/${filename}Tests.cs"
        "$dirname/${filename}Test.cs"
      )
      # Separate test project (ProjectName.Tests/)
      local proj_name
      proj_name=$(basename "$(dirname "$dirname")")
      TEST_CANDIDATES+=(
        "$project_dir/${proj_name}.Tests/${filename}Tests.cs"
        "$project_dir/tests/${filename}Tests.cs"
      )
      ;;
    c|cpp)
      # Common C/C++ test patterns
      TEST_CANDIDATES+=(
        "$dirname/${filename}_test.${ext}"
        "$project_dir/test/${filename}_test.${ext}"
        "$project_dir/tests/${filename}_test.${ext}"
        "$project_dir/test/test_${filename}.${ext}"
        "$project_dir/tests/test_${filename}.${ext}"
      )
      ;;
    scala)
      # Scala: src/test/scala mirrors src/main/scala
      local test_path
      test_path=$(echo "$filepath" | sed 's|/src/main/scala/|/src/test/scala/|' | sed "s|${filename}.scala|${filename}Spec.scala|")
      TEST_CANDIDATES+=("$test_path")
      test_path=$(echo "$filepath" | sed 's|/src/main/scala/|/src/test/scala/|' | sed "s|${filename}.scala|${filename}Test.scala|")
      TEST_CANDIDATES+=("$test_path")
      ;;
    haskell)
      TEST_CANDIDATES+=(
        "$project_dir/test/${filename}Spec.hs"
        "$project_dir/test/${filename}Test.hs"
        "$project_dir/tests/${filename}Spec.hs"
      )
      ;;
  esac
}

# Returns 0 if the project has test infrastructure set up for the given language.
# Usage: has_test_infra "/project" "python" && echo "tests configured"
has_test_infra() {
  local dir="$1"
  local lang="${2:-}"

  # If no language specified, check all
  case "$lang" in
    typescript|javascript|"")
      # Skip TDD enforcement if deps not installed — can't run tests anyway
      if [ -n "$lang" ] && ! has_node_deps_installed "$dir"; then
        return 1
      fi
      # Node.js test frameworks
      for marker in "$dir/jest.config"* "$dir/vitest.config"* "$dir/cypress.config"*; do
        [ -f "$marker" ] 2>/dev/null && return 0
      done
      if [ -f "$dir/package.json" ] && command -v jq &>/dev/null; then
        if jq -e '.scripts.test // .devDependencies.jest // .devDependencies.vitest // .devDependencies.mocha' "$dir/package.json" &>/dev/null; then
          return 0
        fi
      elif [ -f "$dir/package.json" ] && grep -q '"test"' "$dir/package.json" 2>/dev/null; then
        return 0
      fi
      [ -n "$lang" ] && return 1
      ;;&
    python|"")
      [ -f "$dir/pytest.ini" ] && return 0
      [ -f "$dir/setup.cfg" ] && grep -q '\[tool:pytest\]' "$dir/setup.cfg" 2>/dev/null && return 0
      [ -f "$dir/pyproject.toml" ] && grep -q '\[tool.pytest' "$dir/pyproject.toml" 2>/dev/null && return 0
      [ -f "$dir/tox.ini" ] && return 0
      [ -d "$dir/tests" ] && ls "$dir/tests"/test_*.py 1>/dev/null 2>&1 && return 0
      [ -n "$lang" ] && return 1
      ;;&
    go|"")
      [ -f "$dir/go.mod" ] && return 0  # Go has built-in testing
      [ -n "$lang" ] && return 1
      ;;&
    rust|"")
      [ -f "$dir/Cargo.toml" ] && return 0  # Rust has built-in testing
      [ -n "$lang" ] && return 1
      ;;&
    ruby|"")
      [ -f "$dir/Gemfile" ] && grep -qE 'rspec|minitest|test-unit' "$dir/Gemfile" 2>/dev/null && return 0
      [ -d "$dir/spec" ] && return 0
      [ -d "$dir/test" ] && return 0
      [ -n "$lang" ] && return 1
      ;;&
    java|kotlin|"")
      if [ -f "$dir/build.gradle" ] || [ -f "$dir/build.gradle.kts" ]; then
        return 0  # Gradle projects have built-in test support
      fi
      [ -f "$dir/pom.xml" ] && return 0  # Maven projects have built-in test support
      [ -n "$lang" ] && return 1
      ;;&
    elixir|"")
      [ -f "$dir/mix.exs" ] && return 0  # Elixir has built-in testing
      [ -n "$lang" ] && return 1
      ;;&
    swift|"")
      [ -f "$dir/Package.swift" ] && return 0
      [ -n "$lang" ] && return 1
      ;;&
    dart|"")
      [ -f "$dir/pubspec.yaml" ] && return 0
      [ -n "$lang" ] && return 1
      ;;&
    csharp|"")
      ls "$dir"/*.Tests.csproj 1>/dev/null 2>&1 && return 0
      ls "$dir"/tests/*.csproj 1>/dev/null 2>&1 && return 0
      [ -n "$lang" ] && return 1
      ;;&
    scala|"")
      [ -f "$dir/build.sbt" ] && return 0
      [ -n "$lang" ] && return 1
      ;;&
    haskell|"")
      if [ -f "$dir/stack.yaml" ] || ls "$dir"/*.cabal 1>/dev/null 2>&1; then
        return 0
      fi
      [ -n "$lang" ] && return 1
      ;;&
    c|cpp|c_cpp|"")
      [ -f "$dir/CMakeLists.txt" ] && grep -qi 'enable_testing\|add_test\|gtest\|catch2' "$dir/CMakeLists.txt" 2>/dev/null && return 0
      [ -n "$lang" ] && return 1
      ;;
  esac

  return 1
}

# ─── FORMATTER / LINTER DETECTION ─────────────────────────────────────

# Detects the formatter command for a given file.
# Sets: FORMATTER_CMD (string, empty if no formatter found)
# Usage: detect_formatter "/project/src/foo.py" "/project"
detect_formatter() {
  local filepath="$1"
  local project_dir="$2"
  local ext="${filepath##*.}"
  local lang
  lang=$(lang_for_extension "$ext")
  FORMATTER_CMD=""

  case "$lang" in
    typescript|javascript)
      # Skip if node_modules missing — formatters are installed as deps
      if ! has_node_deps_installed "$project_dir"; then
        return 0
      fi

      # Detect Node.js package manager first
      detect_pkg_manager "$project_dir"
      local runner="${PKG_MGR:-npx}"

      if [ -f "$project_dir/biome.json" ] || [ -f "$project_dir/biome.jsonc" ]; then
        FORMATTER_CMD="$runner biome check --write"
      else
        local has_eslint=false
        for f in "$project_dir"/eslint.config.* "$project_dir"/.eslintrc.*; do
          [ -f "$f" ] && has_eslint=true && break
        done
        if [ "$has_eslint" = true ]; then
          FORMATTER_CMD="$runner eslint --fix"
        fi
        # Prettier as standalone or alongside ESLint
        if [ -f "$project_dir/.prettierrc" ] || [ -f "$project_dir/.prettierrc.json" ] || \
           [ -f "$project_dir/prettier.config.js" ] || [ -f "$project_dir/prettier.config.mjs" ]; then
          if [ -n "$FORMATTER_CMD" ]; then
            FORMATTER_CMD="$FORMATTER_CMD \"\$FILE\" && $runner prettier --write"
          else
            FORMATTER_CMD="$runner prettier --write"
          fi
        fi
      fi
      ;;
    python)
      # Ruff (fastest, modern) > Black > autopep8 > yapf
      if command -v ruff &>/dev/null; then
        FORMATTER_CMD="ruff format"
        # Also run ruff check --fix for import sorting + lint fixes
        FORMATTER_CMD="ruff check --fix \"\$FILE\" && ruff format"
      elif command -v black &>/dev/null; then
        FORMATTER_CMD="black"
        # Add isort if available
        if command -v isort &>/dev/null; then
          FORMATTER_CMD="isort \"\$FILE\" && black"
        fi
      elif command -v autopep8 &>/dev/null; then
        FORMATTER_CMD="autopep8 --in-place"
      fi
      # Check pyproject.toml for tool configs
      if [ -z "$FORMATTER_CMD" ] && [ -f "$project_dir/pyproject.toml" ]; then
        if grep -q '\[tool.ruff\]' "$project_dir/pyproject.toml" 2>/dev/null; then
          FORMATTER_CMD="ruff check --fix \"\$FILE\" && ruff format"
        elif grep -q '\[tool.black\]' "$project_dir/pyproject.toml" 2>/dev/null; then
          FORMATTER_CMD="black"
        fi
      fi
      ;;
    go)
      # goimports > gofmt (goimports is a superset)
      if command -v goimports &>/dev/null; then
        FORMATTER_CMD="goimports -w"
      elif command -v gofmt &>/dev/null; then
        FORMATTER_CMD="gofmt -w"
      fi
      ;;
    rust)
      if command -v rustfmt &>/dev/null || command -v cargo &>/dev/null; then
        FORMATTER_CMD="rustfmt"
      fi
      ;;
    ruby)
      if command -v rubocop &>/dev/null; then
        FORMATTER_CMD="rubocop --autocorrect"
      elif [ -f "$project_dir/Gemfile" ] && grep -q 'rubocop' "$project_dir/Gemfile" 2>/dev/null; then
        FORMATTER_CMD="bundle exec rubocop --autocorrect"
      fi
      ;;
    java)
      if command -v google-java-format &>/dev/null; then
        FORMATTER_CMD="google-java-format --replace"
      fi
      # Gradle spotless
      if [ -f "$project_dir/build.gradle" ] && grep -q 'spotless' "$project_dir/build.gradle" 2>/dev/null; then
        FORMATTER_CMD="cd '$project_dir' && ./gradlew spotlessApply"
      fi
      ;;
    kotlin)
      if command -v ktlint &>/dev/null; then
        FORMATTER_CMD="ktlint --format"
      fi
      ;;
    elixir)
      if command -v mix &>/dev/null; then
        FORMATTER_CMD="mix format"
      fi
      ;;
    swift)
      if command -v swift-format &>/dev/null; then
        FORMATTER_CMD="swift-format --in-place"
      elif command -v swiftformat &>/dev/null; then
        FORMATTER_CMD="swiftformat"
      fi
      ;;
    dart)
      if command -v dart &>/dev/null; then
        FORMATTER_CMD="dart format"
      fi
      ;;
    csharp)
      if command -v dotnet &>/dev/null; then
        FORMATTER_CMD="dotnet format"
      fi
      ;;
    c|cpp)
      if command -v clang-format &>/dev/null; then
        FORMATTER_CMD="clang-format -i"
      fi
      ;;
    scala)
      if command -v scalafmt &>/dev/null; then
        FORMATTER_CMD="scalafmt"
      fi
      ;;
    zig)
      if command -v zig &>/dev/null; then
        FORMATTER_CMD="zig fmt"
      fi
      ;;
    haskell)
      if command -v ormolu &>/dev/null; then
        FORMATTER_CMD="ormolu --mode inplace"
      elif command -v fourmolu &>/dev/null; then
        FORMATTER_CMD="fourmolu --mode inplace"
      fi
      ;;
    lua)
      if command -v stylua &>/dev/null; then
        FORMATTER_CMD="stylua"
      fi
      ;;
  esac
}

# ─── TYPE CHECKER DETECTION ───────────────────────────────────────────

# Detects the type checker command for a project.
# Sets: TYPECHECKER_CMD (string), TYPECHECKER_NAME (string)
# Can be called per-language or auto-detect.
# Usage: detect_typechecker "/project" "typescript"
detect_typechecker() {
  local project_dir="$1"
  local lang="${2:-}"
  TYPECHECKER_CMD=""
  TYPECHECKER_NAME=""

  # If no language specified, detect primary
  if [ -z "$lang" ]; then
    detect_project_langs "$project_dir"
    lang="$PRIMARY_LANG"
  fi

  case "$lang" in
    typescript)
      # tsgo (native, fastest) > tsc
      # tsgo detection is complex — handled inline by end-of-turn-typecheck.sh
      # This just returns the basic command
      detect_pkg_manager "$project_dir"
      local runner="${PKG_MGR:-npx}"
      if command -v tsgo &>/dev/null; then
        TYPECHECKER_NAME="tsgo"
        TYPECHECKER_CMD="tsgo"
      else
        TYPECHECKER_NAME="tsc"
        TYPECHECKER_CMD="$runner tsc --noEmit --skipLibCheck"
      fi
      ;;
    python)
      # mypy or pyright
      if command -v pyright &>/dev/null; then
        TYPECHECKER_NAME="pyright"
        TYPECHECKER_CMD="pyright"
      elif command -v mypy &>/dev/null; then
        TYPECHECKER_NAME="mypy"
        TYPECHECKER_CMD="mypy ."
      fi
      # Check pyproject.toml for config
      if [ -z "$TYPECHECKER_CMD" ] && [ -f "$project_dir/pyproject.toml" ]; then
        if grep -q '\[tool.pyright\]' "$project_dir/pyproject.toml" 2>/dev/null; then
          TYPECHECKER_NAME="pyright (configured)"
          TYPECHECKER_CMD="pyright"
        elif grep -q '\[tool.mypy\]' "$project_dir/pyproject.toml" 2>/dev/null; then
          TYPECHECKER_NAME="mypy (configured)"
          TYPECHECKER_CMD="mypy ."
        fi
      fi
      ;;
    go)
      if command -v go &>/dev/null; then
        TYPECHECKER_NAME="go vet"
        TYPECHECKER_CMD="go vet ./..."
      fi
      ;;
    rust)
      if command -v cargo &>/dev/null; then
        TYPECHECKER_NAME="cargo check"
        TYPECHECKER_CMD="cargo check 2>&1"
      fi
      ;;
    java)
      if [ -f "$project_dir/build.gradle" ] || [ -f "$project_dir/build.gradle.kts" ]; then
        TYPECHECKER_NAME="gradle compileJava"
        TYPECHECKER_CMD="cd '$project_dir' && ./gradlew compileJava"
      elif [ -f "$project_dir/pom.xml" ]; then
        TYPECHECKER_NAME="mvn compile"
        TYPECHECKER_CMD="cd '$project_dir' && mvn compile -q"
      fi
      ;;
    kotlin)
      if [ -f "$project_dir/build.gradle.kts" ]; then
        TYPECHECKER_NAME="gradle compileKotlin"
        TYPECHECKER_CMD="cd '$project_dir' && ./gradlew compileKotlin"
      fi
      ;;
    dart)
      if command -v dart &>/dev/null; then
        TYPECHECKER_NAME="dart analyze"
        TYPECHECKER_CMD="dart analyze"
      fi
      ;;
    csharp)
      if command -v dotnet &>/dev/null; then
        TYPECHECKER_NAME="dotnet build"
        TYPECHECKER_CMD="dotnet build --no-restore"
      fi
      ;;
    scala)
      if [ -f "$project_dir/build.sbt" ]; then
        TYPECHECKER_NAME="sbt compile"
        TYPECHECKER_CMD="cd '$project_dir' && sbt compile"
      fi
      ;;
    haskell)
      if command -v stack &>/dev/null; then
        TYPECHECKER_NAME="stack build"
        TYPECHECKER_CMD="stack build --fast --no-run-tests"
      elif command -v cabal &>/dev/null; then
        TYPECHECKER_NAME="cabal build"
        TYPECHECKER_CMD="cabal build"
      fi
      ;;
    swift)
      if command -v swift &>/dev/null; then
        TYPECHECKER_NAME="swift build"
        TYPECHECKER_CMD="swift build"
      fi
      ;;
    zig)
      if command -v zig &>/dev/null; then
        TYPECHECKER_NAME="zig build"
        TYPECHECKER_CMD="zig build"
      fi
      ;;
  esac
}

# ─── DEPENDENCY MANAGEMENT ────────────────────────────────────────────

# Detects the dependency install command for a project.
# Sets: DEP_INSTALL_CMD (string), DEP_LANG (string)
# Usage: detect_dep_install_cmd "/project"
detect_dep_install_cmd() {
  local dir="$1"
  DEP_INSTALL_CMD=""
  DEP_LANG=""

  detect_project_langs "$dir"

  for lang in "${PROJECT_LANGS[@]}"; do
    case "$lang" in
      typescript|javascript)
        detect_pkg_manager "$dir"
        DEP_INSTALL_CMD="${PKG_MGR:-npm} install"
        DEP_LANG="$lang"
        return 0
        ;;
      python)
        if [ -f "$dir/pyproject.toml" ]; then
          if grep -q '\[tool.poetry\]' "$dir/pyproject.toml" 2>/dev/null; then
            DEP_INSTALL_CMD="poetry install"
          elif command -v uv &>/dev/null; then
            DEP_INSTALL_CMD="uv sync"
          elif command -v pip &>/dev/null; then
            DEP_INSTALL_CMD="pip install -e '.[dev]'"
          fi
        elif [ -f "$dir/Pipfile" ]; then
          DEP_INSTALL_CMD="pipenv install --dev"
        elif [ -f "$dir/requirements.txt" ]; then
          DEP_INSTALL_CMD="pip install -r requirements.txt"
        fi
        DEP_LANG="python"
        [ -n "$DEP_INSTALL_CMD" ] && return 0
        ;;
      go)
        DEP_INSTALL_CMD="go mod download"
        DEP_LANG="go"
        return 0
        ;;
      rust)
        DEP_INSTALL_CMD="cargo fetch"
        DEP_LANG="rust"
        return 0
        ;;
      ruby)
        DEP_INSTALL_CMD="bundle install"
        DEP_LANG="ruby"
        return 0
        ;;
      java)
        if [ -f "$dir/gradlew" ]; then
          DEP_INSTALL_CMD="./gradlew dependencies"
        elif [ -f "$dir/mvnw" ]; then
          DEP_INSTALL_CMD="./mvnw dependency:resolve"
        elif command -v gradle &>/dev/null; then
          DEP_INSTALL_CMD="gradle dependencies"
        elif command -v mvn &>/dev/null; then
          DEP_INSTALL_CMD="mvn dependency:resolve"
        fi
        DEP_LANG="java"
        [ -n "$DEP_INSTALL_CMD" ] && return 0
        ;;
      elixir)
        DEP_INSTALL_CMD="mix deps.get"
        DEP_LANG="elixir"
        return 0
        ;;
      dart)
        DEP_INSTALL_CMD="dart pub get"
        DEP_LANG="dart"
        return 0
        ;;
      csharp)
        DEP_INSTALL_CMD="dotnet restore"
        DEP_LANG="csharp"
        return 0
        ;;
      swift)
        DEP_INSTALL_CMD="swift package resolve"
        DEP_LANG="swift"
        return 0
        ;;
      haskell)
        if command -v stack &>/dev/null; then
          DEP_INSTALL_CMD="stack setup"
        elif command -v cabal &>/dev/null; then
          DEP_INSTALL_CMD="cabal update"
        fi
        DEP_LANG="haskell"
        [ -n "$DEP_INSTALL_CMD" ] && return 0
        ;;
      scala)
        if [ -f "$dir/build.sbt" ]; then
          DEP_INSTALL_CMD="sbt update"
        fi
        DEP_LANG="scala"
        [ -n "$DEP_INSTALL_CMD" ] && return 0
        ;;
    esac
  done
}

# ─── DEPENDENCY STATE ────────────────────────────────────────────────

# Returns 0 if Node.js dependencies appear to be installed.
# Checks for a non-empty node_modules directory.
# Usage: has_node_deps_installed "/project" && echo "deps OK"
has_node_deps_installed() {
  local dir="$1"
  [ -d "$dir/node_modules" ] && [ -n "$(ls -A "$dir/node_modules" 2>/dev/null)" ]
}

# ─── FILE EXTENSION HELPERS ───────────────────────────────────────────

# Returns a find-compatible pattern for recent code changes, given a language.
# Usage: code_extensions_for_find "typescript" → "-name '*.ts' -o -name '*.tsx'"
code_extensions_for_lang() {
  case "$1" in
    typescript)       echo "-name '*.ts' -o -name '*.tsx'" ;;
    javascript)       echo "-name '*.js' -o -name '*.jsx' -o -name '*.mjs'" ;;
    python)           echo "-name '*.py'" ;;
    go)               echo "-name '*.go'" ;;
    rust)             echo "-name '*.rs'" ;;
    ruby)             echo "-name '*.rb'" ;;
    java)             echo "-name '*.java'" ;;
    kotlin)           echo "-name '*.kt' -o -name '*.kts'" ;;
    elixir)           echo "-name '*.ex' -o -name '*.exs'" ;;
    swift)            echo "-name '*.swift'" ;;
    c)                echo "-name '*.c' -o -name '*.h'" ;;
    cpp|c_cpp)        echo "-name '*.cpp' -o -name '*.cc' -o -name '*.hpp' -o -name '*.h'" ;;
    csharp)           echo "-name '*.cs'" ;;
    dart)             echo "-name '*.dart'" ;;
    scala)            echo "-name '*.scala'" ;;
    zig)              echo "-name '*.zig'" ;;
    haskell)          echo "-name '*.hs'" ;;
    lua)              echo "-name '*.lua'" ;;
    php)              echo "-name '*.php'" ;;
    *)                echo "" ;;
  esac
}
