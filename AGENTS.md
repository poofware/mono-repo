# Agent Developer Guide

This guide is for AI agents working in a sandboxed environment without Docker access. Your primary responsibility is to modify code, update tests, and validate your changes using static analysis only.

**You must not attempt to run, build, or test the full applications using `make` commands that require Docker (e.g., `up`, `ci`, `run-*`, `build-*`).**

-----

## 1. Backend Development (Go)

Your workflow for backend Go services is focused on a single static analysis step for all validation.

### 1.1. Primary Workflow: Static Analysis and Test Validation

This is the **only required validation step** for Go code. It provides the fastest feedback on the correctness of both your application code and your test code.

1.  **Navigate to the service directory**:
    ```bash
    cd backend/services/<service-name>
    ```
2.  **Add or Update Tests**: Your primary responsibility is to add or update integration tests in `internal/integration/` to match your code changes.

3.  **Run the analyzer**: Run `staticcheck` with the `-tests` flag. This single command will analyze and validate your main application code and your test files, ensuring everything compiles and adheres to standards. It is the preferred tool.
    ```bash
    staticcheck -tests -tags="integration,dev_test" ./...
    ```
    If `staticcheck` is not installed, you can use `go vet` as a fallback.
    ```bash
    go vet -tags="integration,dev_test" ./...
    ```
4.  **You are strictly forbidden from running any compiled binaries or test executables.** The CI pipeline will handle test execution.

### 1.2. Service Compilation (Optional)

After your code and tests pass static analysis, you can optionally perform a compilation of the main service binary to be absolutely certain it builds. This is slower than static analysis and is not a required step.

1.  Navigate to the service directory: `cd backend/services/<service-name>`
2.  Run the build command:
    ```bash
    go build -ldflags="\
    -linkmode external -extldflags '-lm' \
    -X 'github.com/poofware/<service-name>/internal/config.AppName=<service-name>' \
    -X 'github.com/poofware/<service-name>/internal/config.UniqueRunNumber=local-run' \
    -X 'github.com/poofware/<service-name>/internal/config.UniqueRunnerID=local-dev' \
    -X 'github.com/poofware/<service-name>/internal/config.LDServerContextKey=server' \
    -X 'github.com/poofware/<service-name>/internal/config.LDServerContextKind=user'" \
    -o <service-name> ./cmd/main.go
    ```
3.  **You are strictly forbidden from running the compiled service binary.**

-----

## 2. Database Migration Guidelines

When working with database schema changes, you must follow these strict guidelines:

### 2.1. Migration File Management

1. **Always modify the latest migration file** instead of creating new ones
2. **Find the latest migration**: Look for the most recent timestamp in `backend/migrations/` directory
3. **Modify in place**: Add your schema changes to the existing latest migration file
4. **Rationale**: The latest migration represents the current development state and will be deployed to production

### 2.2. Migration Workflow

1. **Locate the latest migration**:
   ```bash
   ls -la backend/migrations/ | tail -5
   ```
2. **Edit the latest `.sql` file** to include your schema changes
3. **Update corresponding Go models** in the service's `internal/models/` directory
4. **Add integration tests** that validate your schema changes work with the updated models
5. **Run static analysis** as described in section 1.1 to validate your changes

### 2.3. Forbidden Actions

- **Never create new migration files** unless explicitly instructed
- **Never run migration commands** or database setup commands
- **Never attempt to connect to databases** - your changes will be validated by CI

-----

## 3. Frontend Development (Flutter/Dart)

Your workflow for the Flutter application is focused exclusively on static analysis.

### 3.1. Primary Workflow: Static Analysis

This is the **only required validation step** for Dart code.

1.  **Navigate to the app directory**:
    ```bash
    cd frontend/apps/worker-app
    ```
2.  **Run the analyzer**:
    ```bash
    # Generate localization files first if you modify .arb files
    flutter gen-l10n --verbose
    
    # Then run the analyzer
    flutter analyze
    ```
3.  **Address analyzer output**: Even if `flutter analyze` only shows informational messages, you must fix important suggestions such as deprecation warnings, performance issues, and code quality improvements.
4.  **You are strictly forbidden from running any `make` commands (`run-*`, `build-*`, `ci-*`).** The `flutter analyze` command is your only validation task.

### 3.2. Testing Requirements

Your responsibility is to **add or update** API integration tests in `frontend/apps/worker-app/integration_test/api/` to reflect any changes made to the data layer (API clients, models).

**You are strictly forbidden from running these tests.** The CI pipeline will handle execution. Your sole validation duty for all Dart code is `flutter analyze`.
