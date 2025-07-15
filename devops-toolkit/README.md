# DevOps Toolkit: Comprehensive README

Welcome to the **DevOps Toolkit**! This toolkit is designed to help you set up robust, modular, and profile-based Docker Compose workflows for your applications. It especially shines with **Go-based microservices**, but it can also be adapted to other projects. 

This README will walk you through:

1. **High-Level Concepts** – Profiles, environment variables, dependency projects, etc.
2. **Basic File Structure** – How the toolkit’s Makefiles and scripts are organized.
3. **Two Usage Patterns**:
   - **Generic Docker Compose Project** (without Go-specific logic).
   - **Go App + Compose Project** (with built-in Go build/test pipelines).
4. **Examples & Common Targets** – Starting containers, running tests, and more.
5. **Advanced Usage** – Overriding profiles, environment variable usage, HCP (HashiCorp Cloud Platform) integration, LaunchDarkly, etc.

Read on to learn how to harness these tools and build consistent workflows for your services.

---

## 1. Key Concepts

### 1.1 Profile-Based Design

Docker Compose supports [profiles](https://docs.docker.com/compose/profiles/) to conditionally include or exclude services. This DevOps Toolkit extends that concept by:

- Defining multiple Compose profiles (e.g., `db`, `migrate`, `app`, `app_pre`, `app_post_check`, `app_integration_test`, etc.).
- Providing Make targets that **spin up** these profiles in a specific order.  
  For example:
  - **`db`** profile for a local Postgres container.  
  - **`migrate`** profile for a migration container.  
  - **`app_pre`** profile for tasks **before** the main application (e.g., a Stripe listener).  
  - **`app`** profile for the main application container.  
  - **`app_post_check`** profile for tasks **after** the main app is running (e.g., health checks).  

By chaining these profiles in `make up`, your environment can be started in easily managed stages rather than with a single `docker compose up` that spins up everything at once.

### 1.2 Dealing with the “unassigned” Profile

In the default Compose YAML files under `devops-toolkit/backend/docker/`, **most services are placed under the `unassigned` profile**. This means they **will not** be automatically started by the toolkit’s default `make up` sequence. 

If you want one of these services to actually spin up in your environment, you **must** override its profile in an additional Compose file—often named `override.compose.yaml`. For example, you can override the `go-app` service so it’s placed in the `app` profile, or override a test container so it goes in `app_integration_test`. Once that override is done, the service becomes an active part of the build/up routines.

### 1.3 Overriding Profiles via Compose Files

Compose supports combining multiple files via `COMPOSE_FILE` (colon-separated) so you can:

- Keep a base Compose file in your toolkit (e.g., `go-app.compose.yaml`), where services might be labeled with `profiles: [unassigned]`.
- Add an environment- or project-specific override in your own `override.compose.yaml` that **re-assigns** these services to active profiles like `db`, `app`, `migrate`, etc.
- Use `make up` to start only those services assigned to the relevant profiles (e.g., `app`, `db`, `migrate`, `app_pre`, `app_post_check`).

### 1.4 Makefile Inclusions

The toolkit has **many** small `*.mk` files in `devops-toolkit/backend/make/`. You include them in your project’s root `Makefile` to gain standardized targets such as `build`, `up`, `down`, `clean`, `integration-test`, `ci`, etc.

### 1.5 Environment Variables

Several env vars control how the build and runs happen, for example:

- `ENV` – Distinguishes dev/staging/prod (or `dev-test`).
- `COMPOSE_PROJECT_NAME` – Compose project name (unique for each microservice or service).
- `COMPOSE_NETWORK_NAME` – Name of the shared docker network.
- `WITH_DEPS` – Whether to recursively run targets in **dependency projects**.
- `DEPS` – A space-separated list of “dependency projects” (with optional `key:path` format).

For Go apps, additional variables come into play:

- `APP_NAME`, `APP_PORT` – The name and port for the Go service.
- `APP_URL_FROM_COMPOSE_NETWORK` – The address other containers use to reach your service internally.
- `APP_URL_FROM_ANYWHERE` – The external address (on your local machine).
- `PACKAGES` – Additional internal Go modules to fetch and keep updated.

### 1.6 Dependency Projects

If your app depends on other local projects (e.g., libraries, microservices, or any other codebase following the same Make contract), you can specify them via:

```
WITH_DEPS ?= 1
DEPS := "PROJECT_KEY:/path/to/dependency-project"
```

When you run a Make target (e.g., `make up`), it will also invoke the same target on each listed dependency project, in sequence.

---

## 2. File Structure

A typical repository that uses the DevOps Toolkit might look like this:

```
.
├─ Makefile                          # Root Makefile for your service
├─ devops-toolkit/                   # The toolkit, possibly included as a submodule
│  ├─ backend/make/                  # A library of .mk files
│  ├─ backend/scripts/               # Reusable Bash scripts (token fetch, encryption, etc.)
│  └─ backend/docker/                # Base Dockerfiles, docker-compose YAMLs
└─ override.compose.yaml             # (Optional) Additional compose overrides
```

Inside `devops-toolkit/backend` you’ll see numerous scripts (e.g., `fetch_hcp_api_token.sh`, `fetch_hcp_secret.sh`, `encryption.sh`) and Dockerfiles for specialized tasks (Go builds, DB migrations, Stripe CLI, etc.).

---

## 3. Setting Up a **Regular** Docker Compose Project

### 3.1 Minimal Root Makefile (Generic Example)

If you don’t have a Go-based service but still want to leverage this profile-based approach, you can do something like:

```makefile
# -------------------------
# Root Makefile for "my-service"
# -------------------------

ENV ?= dev-test
COMPOSE_PROJECT_NAME := my-service
COMPOSE_NETWORK_NAME ?= shared_service_network

# If you have no other local dependency projects, set:
WITH_DEPS ?= 0
DEPS := ""

# Compose files to include (colon-separated)
COMPOSE_FILE := \
  devops-toolkit/backend/docker/db.compose.yaml:\
  devops-toolkit/backend/docker/stripe.compose.yaml:\
  override.compose.yaml

# 1) Include project configuration (handles environment, profiles, etc.)
ifndef INCLUDED_COMPOSE_PROJECT_CONFIGURATION
  include devops-toolkit/backend/make/compose/compose_project_configuration.mk
endif

# 2) Include standard project targets (build, up, down, clean, integration-test, etc.)
ifndef INCLUDED_COMPOSE_PROJECT_TARGETS
  include devops-toolkit/backend/make/compose/compose_project_targets.mk
endif
```

Now, **be aware** that most of the services defined in `db.compose.yaml` or `stripe.compose.yaml` might be set to `profiles: [unassigned]` by default. So to actually **run** them, you need to override them in `override.compose.yaml` (or a similarly named file) to place them in an active profile like `db` or `app`. Example:

```yaml
# override.compose.yaml
services:
  db:
    profiles:
      - db

  stripe-listener:
    profiles:
      - app_pre
```

Now, `make up` will see `db` is in the `db` profile, etc., and spin them up in the right order.

### 3.2 Using the Make Targets

From your shell in the project root:

- **`make build`**  
  Builds Docker images for any services whose profiles (or no profile) you’ve assigned to the build sequence.
- **`make up`**  
  Starts containers in an order: `db → migrate → app_pre → app → app_post_check`. Only those services that are actually assigned these profiles will come up.
- **`make integration-test`**  
  (If you set up an integration-test profile) runs that ephemeral test container.
- **`make down`**  
  Stops and removes containers (but leaves images).
- **`make clean`**  
  Fully stops and removes containers, images, volumes, networks, etc.

---

## 4. Setting Up a **Go App** + Docker Compose Project

Many `.mk` files and Dockerfiles in this toolkit focus on simplifying Go builds, tests, and multi-stage Docker builds. Below is a real-world template (inspired by an `account-service` example).

### 4.1 Example: Root Makefile for a Go Service

```makefile
# -------------------------
# Root Makefile for "account-service"
# -------------------------

# 1) Basic Service Settings
ENV ?= dev-test
COMPOSE_PROJECT_NAME := account-service
COMPOSE_NETWORK_NAME ?= shared_service_network

WITH_DEPS ?= 0
DEPS := ""  # No dependent projects in this example

COMPOSE_FILE := \
  devops-toolkit/backend/docker/go-app.compose.yaml:\
  devops-toolkit/backend/docker/db.compose.yaml:\
  devops-toolkit/backend/docker/stripe.compose.yaml:\
  override.compose.yaml

# 2) Include the Compose Project Configuration
ifndef INCLUDED_COMPOSE_PROJECT_CONFIGURATION
  include devops-toolkit/backend/make/compose/compose_project_configuration.mk
endif

# 3) Go App–specific Compose Configuration
#    - Tells the system which port your Go app runs on, etc.
export APP_NAME := $(COMPOSE_PROJECT_NAME)
export APP_PORT ?= 8080
ifndef INCLUDED_GO_APP_COMPOSE_CONFIGURATION
  include devops-toolkit/backend/make/go-app/go_app_compose_configuration.mk
endif

# 4) Additional DB Migrations Config
export COMPOSE_DB_NAME := shared_pg_db
export MIGRATIONS_PATH := migrations
export HCP_APP_NAME_FOR_DB_SECRETS := $(APP_NAME)-$(ENV)

# 5) Stripe Example Config
export STRIPE_WEBHOOK_CONNECTED_EVENTS := \
  account.updated,capability.updated,identity.verification_session.created,\
  identity.verification_session.requires_input,identity.verification_session.verified,\
  identity.verification_session.canceled,payment_intent.created
export STRIPE_WEBHOOK_ROUTE := /api/v1/account/stripe/webhook
export STRIPE_WEBHOOK_CHECK_ROUTE := /api/v1/account/stripe/webhook/check

# 6) Finally, bring in the standard Compose project targets
ifndef INCLUDED_COMPOSE_PROJECT_TARGETS
  include devops-toolkit/backend/make/compose/compose_project_targets.mk
endif

# 7) Go App Targets (build, test, update, etc.)
PACKAGES := go-middleware go-repositories go-utils go-models
ifndef INCLUDED_GO_APP_TARGETS
  include devops-toolkit/backend/make/go-app/go_app_targets.mk
endif
```

### 4.2 Overriding the Test Container with `override.compose.yaml`

Your project might introduce an additional Compose file (`override.compose.yaml`) to properly assign services to active profiles. For instance:

```yaml
# override.compose.yaml

services:
  go-app-integration-test:
    profiles:
      - base_app_integration_test

  go-app-integration-test-override:
    extends:
      file: devops-toolkit/backend/docker/go-app.compose.yaml
      service: go-app-integration-test
    container_name: ${APP_NAME}-integration-test-override_instance
    profiles:
      - app_integration_test
    build:
      context: .
      dockerfile: override.Dockerfile
      target: integration-test-runner-override

  go-app:
    profiles:
      - app

  go-app-health-check:
    profiles:
      - app_post_check

  db:
    profiles:
      - db

  migrate:
    profiles:
      - migrate

  stripe-listener:
    profiles:
      - app_pre

  stripe-webhook-check:
    profiles:
      - app_post_check
```

Notice in the base `go-app.compose.yaml` these services might have been defined with `profiles: [unassigned]`. Now in `override.compose.yaml`, we **reassign** them to `app`, `db`, `app_pre`, etc. This ensures they actually come up when you run `make up`.

### 4.3 Common Make Targets

- **`make up`**  
  *In order*, it will bring up `db → migrate → app_pre → app → app_post_check`.  
  Only those services assigned to these profiles will actually start.
- **`make integration-test`**  
  Spins up the `app_integration_test` profile, which typically runs ephemeral integration tests, then tears down.
- **`make clean`**  
  Removes everything: containers, images, volumes, and networks.

---

## 5. Activating or Excluding Profiles

By default, the internal `make up` logic looks for these profiles in a specific order: `db → migrate → app_pre → app → app_post_check`. Services that remain on `unassigned` are **ignored** (they will never start).

You can also **exclude** certain phases, using environment variables:

- `EXCLUDE_COMPOSE_PROFILE_APP=1` – Skips the `app` profile.  
- `EXCLUDE_COMPOSE_PROFILE_APP_POST_CHECK=1` – Skips the `app_post_check` profile.  

Example:
```bash
EXCLUDE_COMPOSE_PROFILE_APP=1 make up
```
This starts only `db` and `migrate` and `app_pre`, skipping the main application container.

---

## 6. Working with Dependency Projects

If your service depends on other local projects—libraries or microservices—that also implement the same Make targets:

1. **Set** `WITH_DEPS=1`.
2. **Define** your dependency projects in `DEPS` as a space-separated list.  
   Example:
   ```makefile
   WITH_DEPS ?= 1
   DEPS := \
     "AUTH_SERVICE:../auth-service" \
     "CONFIG_SERVICE:../config-service"
   ```
3. When you run `make up`, your Makefile will:
   - Jump into each of those `DEPS` paths and run `make up` first.
   - Then proceed with your own `up`.

This fosters a multi-repo environment where one project can automatically spin up any projects it depends on.

---

## 7. Updating Go Modules

If you’re building a Go service that references internal Git repositories (like `github.com/poofware` modules), you can do:

- **`make update`**  
  - This target calls `update_go_packages.sh`, which fetches each package in `PACKAGES` on a given `BRANCH`.
  - Then runs `go mod tidy` and optionally `make vendor` if needed.

Example usage:

```bash
BRANCH=main PACKAGES="go-middleware go-utils go-models" make update
```

---

## 8. HCP & LaunchDarkly Integration

This toolkit includes scripts to:

- **Fetch and cache an HCP (HashiCorp Cloud Platform) API token**.  
- **Encrypt/Decrypt secrets** at rest with `openssl`.
- **Pull secrets from HCP** for your environment, such as database URLs.  
- **Fetch LaunchDarkly flags** for feature toggles in ephemeral containers.

Most features are optional. If your environment doesn’t use HCP or LaunchDarkly, you can simply omit referencing those scripts or environment variables.

---

## 9. Putting It All Together

Here’s the typical flow when using the DevOps Toolkit in your local dev environment:

1. **Set up environment variables** in your shell:
   ```bash
   export HCP_CLIENT_ID="xxx"
   export HCP_CLIENT_SECRET="yyy"
   export HCP_TOKEN_ENC_KEY="some-random-key"
   export UNIQUE_RUNNER_ID="my-username"
   ```
2. **`make build`** – Build Docker images for your service (and any dependency projects if `WITH_DEPS=1`).
3. **`make up`** – Start the environment in a layered approach: `db → migrate → app_pre → app → app_post_check`.  
   (All of these assume you **overrode** the `unassigned` profile for each relevant service to something active!)
4. **(Optional) `make integration-test`** – Run an ephemeral container that tests your service’s integration logic.
5. **`make down`** – Stop all containers for this project.
6. **`make clean`** – Clean up everything including volumes, images, etc.

Through the profile-based approach, you can finely tune which containers or tasks run in each step. Overriding or adding new profiles is straightforward by layering additional Compose files.

---

## 10. Conclusion

**The DevOps Toolkit** streamlines multi-stage Docker Compose usage, especially for Go-based applications. With a minimal root `Makefile`, you gain consistent commands like `make up`, `make down`, `make build`, `make test`, `make ci`, etc.—complete with flexible **profile-based** logic and optional **dependency chaining**.

**Key takeaways**:
- You include a few `.mk` files to get out-of-the-box commands.
- You set environment variables to fit your service name, network, ports, etc.
- You override the `unassigned` profile in your own `override.compose.yaml` to ensure that the services you care about actually run under `app`, `db`, etc.
- You combine Compose files to support a multi-stage, profile-driven container orchestration.

Enjoy building your services with confidence and consistency using the DevOps Toolkit!

---

**Questions or issues?**  
- Check the comments in the included `.mk` files—many contain usage instructions.  
- Examine example services (like `account-service`) to see how advanced features are used.  
- Adapt the toolkit to suit your internal needs.

Happy hacking!
