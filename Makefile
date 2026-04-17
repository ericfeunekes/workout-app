# Common commands for local development. Every target is a thin wrapper over
# uv / swift so the source of truth stays in pyproject.toml and Package.swift.

.PHONY: help setup dev test test-python test-swift lint format check regen-schema clean

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

clean:  ## Remove .pytest_cache, .ruff_cache, schema/.build
	rm -rf .pytest_cache .ruff_cache schema/.build
