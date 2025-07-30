# Developer Guide

Welcome to the monorepo! This guide provides all the necessary information for developers to get started with setting up, running, and testing the services and applications.

-----

## 1. Prerequisites

Before you begin, ensure you have the following tools installed on your system:

  - **Git:** For version control.
  - **Docker & Docker Compose:** For running backend services in a containerized environment.
  - **GNU Make:** Version 4.4 or higher is recommended. The build system relies heavily on Makefiles.
  - **Go:** Version 1.24 or higher for backend development.
  - **Flutter:** The stable channel is recommended for mobile app development.
  - **Node.js:** For frontend web development.
  - **Bitwarden Secrets Manager CLI (`bws`):** For accessing secrets.

You will also need a Bitwarden access token (`BWS_ACCESS_TOKEN`) exported as an environment variable to fetch necessary secrets for local development.

-----

## 2. Project Architecture

This monorepo contains backend microservices written in Go and frontend applications built with Flutter and standard web technologies.

  - **Backend:** A collection of Go microservices located in `backend/services/`. These services are containerized with Docker and managed via Makefiles. The `backend/meta-service` acts as a gateway, orchestrating and exposing all other backend services for local development.
  - **Frontend:** Applications are located in `frontend/apps/`. This includes the Flutter-based `worker-app` for iOS and Android, and `the-website` for the public-facing web presence.
  - **Shared Libraries:** Common code is shared across projects. Go packages are in `backend/shared/`, and Flutter packages are in `frontend/shared/`.

-----

## 3. Core Concepts

### Secrets Management (Bitwarden)

All secrets (API keys, database URLs, etc.) are managed in Bitwarden Secrets Manager. The `bws` CLI tool, combined with a `BWS_ACCESS_TOKEN`, is used to fetch these secrets at build time.

  - **Authentication:** You must have the `BWS_ACCESS_TOKEN` environment variable set in your shell.
  - **Usage:** The Makefiles and Dockerfiles are configured to automatically fetch the required secrets for the environment (`dev`, `staging`, etc.) you are working in. You do not need to manually run `bws` commands.

### Database Migrations (Tern)

Database schema changes are managed through SQL migration files located in `backend/migrations`. We use `tern` to apply these migrations.

  - **Running Migrations:** Migrations are run automatically as part of the `make up` or `make ci` process. To run them manually:

    ```bash
    # From a service directory, e.g., backend/services/account-service
    make migrate
    ```

  - **Creating a New Migration:** Use the `tern new` command. Ensure you are in a directory with a configured `tern.conf` file or provide the path to your migrations.

### Key Environment Variables

You can override the behavior of the build system by setting these variables when running `make` commands.

  - **`ENV`**: Specifies the target environment. This is the most important variable as it controls which configuration, secrets, and deployment targets are used.

      - `dev-test` (Default): For local development and testing. Connects to local Docker services.
      - `dev`: Similar to `dev-test`.
      - `staging`: For deployments to the staging environment on Fly.io.
      - `prod`: For deployments to the production environment on Fly.io.
      - **Usage:** `make up ENV=staging`

  - **`AUTO_LAUNCH_BACKEND`**: (Frontend) Automatically starts the backend (`meta-service`) when running frontend tasks like `run-ios` or `ci-android`.

      - `1` (Default): The backend is started automatically. Ideal for frontend-focused work.
      - `0`: The backend is not started automatically. Useful if you are managing the backend stack manually in a separate terminal.
      - **Usage:** `AUTO_LAUNCH_BACKEND=0 make run-android`

  - **`PARA_DEPS`**: (Backend) Controls whether dependency tasks are executed in parallel or sequentially.

      - `1` (Default): Runs dependency tasks in parallel for faster execution.
      - `0`: Runs dependency tasks sequentially. The output is cleaner and easier to debug if there are issues with a specific dependency.
      - **Usage:** `PARA_DEPS=0 make up` (from `backend/meta-service`)

-----

## 4. Backend Development

All backend services are designed to be run within Docker containers. The `meta-service` is the primary entry point for running the entire backend stack locally.

### Running the Full Backend Stack

For most development, you will want to run all backend services simultaneously.

1.  **Navigate to the meta-service directory:**

    ```bash
    cd backend/meta-service
    ```

2.  **Start all services:**

    ```bash
    make up
    ```

    This command will:

      - Create a shared Docker network.
      - Build Docker images for all dependent services (`auth-service`, `account-service`, etc.).
      - Start all services in detached mode.
      - Set up a local gateway with `ngrok` to expose the services to your frontend applications. The public URL will be printed in the console.

### Running Individual Services

While developing a specific service, you can run its build and test commands individually from its directory.

  - **Build:** `make build` - This command compiles the service to ensure it builds successfully. It does not run the service.
  - **Test:** `make ci` - This command runs the continuous integration pipeline for the service, which typically includes building the code, running database migrations, and executing integration tests within a clean Docker environment.

Below are the paths for each service:

| Service            | Path                              | Build Command  | Test Command |
| ------------------ | --------------------------------- | -------------- | ------------ |
| **account-service**| `backend/services/account-service`| `make build`   | `make ci`    |
| **auth-service** | `backend/services/auth-service`   | `make build`   | `make ci`    |
| **earnings-service**| `backend/services/earnings-service`| `make build`   | `make ci`    |
| **interest-service**| `backend/services/interest-service`| `make build`   | `make ci`    |
| **jobs-service** | `backend/services/jobs-service`   | `make build`   | `make ci`    |
| **meta-service** | `backend/meta-service`            | `make build`   | `make ci`    |

-----

## 5. Frontend Development

Frontend applications connect to the backend stack running via the `meta-service`.

### Worker App (Flutter)

The `worker-app` is a cross-platform mobile application for gig workers.

  - **Path:** `frontend/apps/worker-app`

#### Setup

1.  **Install Dependencies:** Before running the app, install the necessary Flutter and native dependencies:
      - For iOS: `make dependencies-ios`
      - For Android: `make dependencies-android`

#### Running the App

Run the app on an emulator, simulator, or physical device. The `run` commands will automatically start the backend stack if it's not already running (`AUTO_LAUNCH_BACKEND=1` is the default).

  - **Run on Android:** `make run-android`
  - **Run on iOS:** `make run-ios`

#### Building and Testing

  - **Build (Android):** `make build-android`
  - **Test (Android):** `make ci-android`
  - **Build (iOS):** `make build-ios`
  - **Test (iOS):** `make ci-ios`

### The Website (Web)

This is the main public-facing website.

  - **Path:** `frontend/apps/the-website`
  - **Build:** `make build-web`
  - **Test:** `make ci-web`

-----

## 6. Full-Stack Workflow

1.  **Start the Backend:** In a terminal, navigate to `backend/meta-service` and run `make up`. Note the ngrok URL that is output.
2.  **Configure Frontend:** The frontend applications are configured to use the backend gateway URL provided during the build process. For local development, this is handled automatically by the Makefiles.
3.  **Run the Frontend:** In a separate terminal, navigate to the desired frontend app directory (e.g., `frontend/apps/worker-app`) and run the corresponding `make run-[platform]` command. The app will connect to the local backend stack.
4.  **Develop:** Make changes to your frontend or backend code. The Go services and Flutter app support hot-reloading for a fast development cycle.

-----

## 7. Deployment

Deployments are handled via GitHub Actions and target [Fly.io](https://fly.io).

  - **Staging:** The `staging` environment is deployed automatically from the `develop` branch for backend services and the `testflight`/`playstore` branches for mobile apps.
  - **Production:** The `prod` environment is deployed automatically from the `main` branch.

The Makefiles in each service contain `deploy-[platform]` targets that are used by the CI/CD pipelines. Manual deployments are generally not required.

-----

## 8. CI/CD

The repository is configured with GitHub Actions for continuous integration and deployment. Workflows are located in the `.github/workflows` directory. Pushes to `develop`, `main`, `testflight`, and `playstore` branches will trigger the respective build, test, and deployment pipelines.

-----

## 9. Local Compilation (Without Docker)

For developers who cannot use Docker or prefer a native Go workflow, each backend service can be compiled and run directly on the host machine.

### Prerequisites

  - Go version 1.24 or higher must be installed and available in your system's `PATH`.
  - You must have a `BWS_ACCESS_TOKEN` exported in your shell to fetch application secrets.

### Compilation Steps

Each Go service uses build-time variables (`ldflags`) to inject configuration like the application name and build details. The following command template can be used to compile any service.

1.  **Navigate to the service directory**:

    ```bash
    cd backend/services/<service-name>
    ```

2.  **Build the binary**: Use the `go build` command with the appropriate `ldflags`. The `-o` flag specifies the output binary name.

    **General Command:**

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

### Service-Specific Instructions

Use the following table to substitute the correct `<service-name>` in the compilation command above for each microservice.

| Service              | `<service-name>`   |
| -------------------- | ------------------ |
| **account-service** | `account-service`  |
| **auth-service** | `auth-service`     |
| **earnings-service** | `earnings-service` |
| **interest-service** | `interest-service` |
| **jobs-service** | `jobs-service`     |

-----

## 10. Local Testing (Without Docker)

When Docker is unavailable, you can still run the integration tests by manually setting up the necessary components: a PostgreSQL database and the service executable.

### 10.1. Step 1: Running a Local Database

The services require a PostgreSQL database. Install it using a package manager like Homebrew (macOS) or APT (Debian/Ubuntu).

```bash
# macOS
brew install postgresql

# Debian/Ubuntu
sudo apt-get update
sudo apt-get install postgresql
```

After installation, ensure the database is running and create the user and database that the services expect:

  - **User**: `user`
  - **Password**: `password`
  - **Database**: `mydatabase`

### 10.2. Step 2: Running Database Migrations

Before launching the service, you must apply the database schema. This is handled by the `tern` migration tool.

1.  **Install Tern**:

    ```bash
    go install "github.com/jackc/tern/v2@v2.3.2"
    ```

2.  **Run Migrations**: From the `backend` directory, run the following command to apply all migrations from the `backend/migrations` folder to your local database.

    ```bash
    # Make sure you are in the 'backend' directory
    tern migrate --migrations ./migrations --conn-string "postgres://user:password@localhost:5432/mydatabase"
    ```

### 10.3. Step 3: Running the Service

With the database migrated, the service can be compiled and run on a local port.

1.  **Navigate to the service directory** (e.g., `backend/services/account-service`).

2.  **Compile the service binary** using the `go build` command from Section 9.

3.  **Run the executable** with the required environment variables.

    ```bash
    export BWS_ACCESS_TOKEN="your_token_here"
    export ENV="dev-test"
    export APP_PORT="8083" # Use the port for the specific service
    export APP_URL_FROM_ANYWHERE="http://localhost:8083"
    export DB_URL="postgres://user:password@localhost:5432/mydatabase"

    ./account-service
    ```

### 10.4. Step 4: Running the Tests

With the database and service running, you can now execute the integration tests.

1.  **Compile the test binary**: The test files are compiled into a separate executable.

    ```bash
    go test -c -tags "dev-test,integration" -o integration.test ./internal/integration/...
    ```

2.  **Run the test executable**: Set the `APP_URL_FROM_COMPOSE_NETWORK` variable to point to your locally running service.

    ```bash
    export BWS_ACCESS_TOKEN="your_token_here"
    export APP_URL_FROM_COMPOSE_NETWORK="http://localhost:8083"

    ./integration.test -test.v
    ```

It is crucial to **always run all tests after any code change**. This ensures your modifications align with the production services and that the project remains buildable and stable.

-----

## 11. Flutter Development (Without Docker)

The Flutter build process does not require Docker for the frontend itself. However, running the app or its tests requires a live backend, which is too complex to set up without the Docker pipeline.

Therefore, when Docker is not available, the primary goal is to **ensure the Flutter code compiles successfully**.

### 11.1. Building the App

Use the existing `make` targets to build the Flutter application for each platform. This verifies that your code changes have not introduced any compilation errors.

1.  **Navigate to the app directory**:

    ```bash
    cd frontend/apps/worker-app
    ```

2.  **Run the build command**:

    ```bash
    # Build for Android
    make build-android

    # Build for iOS
    make build-ios
    ```

### 11.2. A Note on Testing

**Do not attempt to run Flutter tests without Docker.** The end-to-end and integration tests for Flutter depend on the full backend stack managed by `docker-compose`. Setting this up manually is not a supported workflow. Your responsibility is to ensure the code compiles, and the CI/CD pipeline will handle the full test suite.
