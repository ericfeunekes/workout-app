# Common commands for local development. Every target is a thin wrapper over
# uv / swift so the source of truth stays in pyproject.toml and Package.swift.

.PHONY: help setup dev test test-python test-swift test-core lint format check regen-schema xcodegen clean \
        db-backup db-restore deploy deploy-rollback server-status server-logs

# Deploy / ops targets. Override HOST on the command line (e.g. `make deploy HOST=workoutdb.tail-xyz.ts.net`).
HOST ?= workoutdb-server
TAG  ?= main

# Resolve the local SQLite path. Precedence: $WORKOUTDB_DB_PATH in the shell env,
# then .env's WORKOUTDB_DB_PATH, then ./workoutdb.sqlite. The server process may be
# running; SQLite's online backup API (`sqlite3_backup_*`) is safe here.
_ENV_DB_PATH := $(shell awk -F= '/^WORKOUTDB_DB_PATH=/{print $$2}' .env 2>/dev/null)
LOCAL_DB_PATH ?= $(if $(WORKOUTDB_DB_PATH),$(WORKOUTDB_DB_PATH),$(if $(_ENV_DB_PATH),$(_ENV_DB_PATH),./workoutdb.sqlite))

help:  ## Show this help
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*?##/ {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

setup:  ## One-time: install deps + pre-commit hooks
	uv sync --extra dev
	uv run pre-commit install --hook-type pre-commit --hook-type pre-push

dev:  ## Run the server with auto-reload (loads .env)
	uv run uvicorn workoutdb_server.main:app --reload

test: test-python test-swift  ## Run Python + Swift tests

test-python:  ## Run Python tests (server + contract)
	uv run pytest

test-swift:  ## Run Swift schema package tests
	cd schema && swift test

test-core:  ## Run all Core + Sync Swift package tests (CLT-compatible)
	cd app/Packages/Core/Foundation && swift run WorkoutCoreFoundationTests
	cd app/Packages/Core/Domain && swift run CoreDomainTests
	cd app/Packages/Core/Prescription && swift run CorePrescriptionTests
	cd app/Packages/Core/Autoreg && swift run CoreAutoregTests
	cd app/Packages/Core/Session && swift run CoreSessionTests
	cd app/Packages/Sync && swift run SyncTests

lint:  ## ruff check + import-linter
	uv run ruff check .
	uv run lint-imports

format:  ## ruff format
	uv run ruff format .

check: lint  ## Full verification (ruff format --check + ruff check + lint-imports + pytest + swift test)
	uv run ruff format --check .
	uv run pytest
	cd schema && swift test

regen-schema:  ## Regenerate schema/openapi.json from the live FastAPI app
	WORKOUTDB_BEARER_TOKEN=dummy WORKOUTDB_DB_PATH=/tmp/dummy.db \
	  uv run python -c "import json; from workoutdb_server.main import app; print(json.dumps(app.openapi(), indent=2))" \
	  > schema/openapi.json

xcodegen:  ## Regenerate app/WorkoutDB.xcodeproj from app/project.yml
	cd app && xcodegen generate

clean:  ## Remove .pytest_cache, .ruff_cache, schema/.build, app/.build, Xcode DerivedData
	rm -rf .pytest_cache .ruff_cache schema/.build
	rm -rf app/Packages/*/.build app/Packages/Core/*/.build
	rm -rf app/DerivedData

# ---------- DB backup / restore ----------

db-backup:  ## Online SQLite snapshot of $$WORKOUTDB_DB_PATH (from .env) into ./backups/
	@mkdir -p backups
	@ts=$$(date -u +%Y%m%dT%H%M%SZ); \
	 dest=backups/workoutdb-$$ts.sqlite; \
	 echo "Backing up $(LOCAL_DB_PATH) -> $$dest"; \
	 uv run python deploy/db_backup.py "$(LOCAL_DB_PATH)" "$$dest"

db-restore:  ## Restore FILE=... over $$WORKOUTDB_DB_PATH (prompts y/N). Stop the server first.
	@test -n "$(FILE)" || { echo "usage: make db-restore FILE=backups/workoutdb-...sqlite"; exit 2; }
	@test -f "$(FILE)" || { echo "file not found: $(FILE)"; exit 2; }
	@echo "About to overwrite $(LOCAL_DB_PATH) with $(FILE)."
	@printf "Proceed? [y/N] "; read ans; \
	 case "$$ans" in \
	   y|Y|yes|YES) cp -v "$(FILE)" "$(LOCAL_DB_PATH)";; \
	   *) echo "aborted"; exit 1;; \
	 esac

# ---------- Deploy / ops ----------

deploy:  ## Deploy to $$HOST (tailnet). Rsync, install, symlink flip, restart. Override TAG= for a specific ref.
	./deploy/deploy.sh $(HOST) $(TAG)

deploy-rollback:  ## Roll back $$HOST to the previous release dir.
	./deploy/rollback.sh $(HOST)

server-status:  ## Show launchd status + /health/ready via SSH to $$HOST.
	ssh $(HOST) 'sudo launchctl print system/com.ericfeunekes.workoutdb 2>/dev/null || echo "service not loaded"; curl -fsSL http://localhost:$${WORKOUTDB_PORT:-8080}/health/ready || echo "api unreachable"'

server-logs:  ## Tail the server logs on $$HOST.
	ssh $(HOST) 'tail -200 -f /opt/workoutdb/shared/logs/stderr.log'
