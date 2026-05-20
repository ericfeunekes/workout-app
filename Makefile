# Common commands for local development. Every target is a thin wrapper over
# uv / swift so the source of truth stays in pyproject.toml and Package.swift.

.PHONY: help setup dev test test-python test-swift test-core test-app-packages test-app-xcode test-execution-ui test-settings-ui test-workout-type-ui test-workout-type-ui-repeat test-tokenstore-keychain-ui test-healthkit-ui test-healthkit-watch-sim assert-healthkit-watch-sim-log \
        test-sync-real-http check-app pre-qa lint format check regen-schema xcodegen xcode-mcp-tools qa-ready qa-runtime-ready clean \
        release-bump-build release-preflight release-testflight release-status release-resume db-backup db-restore deploy deploy-rollback server-status server-logs

# Deploy / ops targets. Override HOST on the command line (e.g. `make deploy HOST=workoutdb.tail-xyz.ts.net`).
HOST ?= workoutdb-server
TAG  ?= main

# Resolve the local SQLite path. Precedence: $WORKOUTDB_DB_PATH in the shell env,
# then .env's WORKOUTDB_DB_PATH, then ./workoutdb.sqlite. The server process may be
# running; SQLite's online backup API (`sqlite3_backup_*`) is safe here.
_ENV_DB_PATH := $(shell awk -F= '/^WORKOUTDB_DB_PATH=/{print $$2}' .env 2>/dev/null)
LOCAL_DB_PATH ?= $(if $(WORKOUTDB_DB_PATH),$(WORKOUTDB_DB_PATH),$(if $(_ENV_DB_PATH),$(_ENV_DB_PATH),./workoutdb.sqlite))
XCODE_MCP_PATH := /usr/local/bin:/opt/homebrew/bin:$(PATH)
XCODEGEN_PATH := /usr/local/bin:/opt/homebrew/bin:$(PATH)
IOS_SIMULATOR ?= iPhone 17
XCODE_RESULT_ROOT ?= /tmp/workoutdb-xcresults-$(shell date +%Y%m%d%H%M%S)
WORKOUT_TYPE_UI_REPEAT_COUNT ?= 3
HEALTHKIT_PREFLIGHT_DERIVED_DATA ?= $(XCODE_RESULT_ROOT)/HealthKitEntitlementPreflight
PROBE_LOG ?=
RELEASE_CONFIG ?=
RELEASE_ARGS := $(if $(RELEASE_CONFIG),--config $(RELEASE_CONFIG),)
RELEASE_REF ?= HEAD
RELEASE_PREFLIGHT_ARGS := $(if $(RELEASE_SKIP_REMOTE),--skip-remote,)
RELEASE_GATE_CMD ?= make pre-qa
RELEASE_GATE_ARGS := $(if $(RELEASE_GATE_OVERRIDE),--gate-override "$(RELEASE_GATE_OVERRIDE)",--gate-cmd "$(RELEASE_GATE_CMD)")
RELEASE_VERSION ?=
RELEASE_BUILD ?=

WORKOUT_TYPE_UI_TESTS := \
	testStraightSetsCanLaunchPerformOneActionAndEnd \
	testSupersetCanLaunchPerformOneActionAndEnd \
	testCircuitCanLaunchPerformOneActionAndEnd \
	testContinuousCanLaunchPerformOneActionAndEnd \
	testAccumulateCanLaunchPerformOneActionAndEnd \
	testCustomCanLaunchPerformOneActionAndEnd \
	testRestCanLaunchPerformOneActionAndEnd \
	testEmomCanLaunchPerformOneActionAndEnd \
	testAmrapCanLaunchPerformOneActionAndEnd \
	testForTimeCanLaunchPerformOneActionAndEnd \
	testIntervalsCanLaunchPerformOneActionAndEnd \
	testTabataCanLaunchPerformOneActionAndEnd \
	testTimerGauntletStrengthCanLaunchPerformOneActionAndEnd \
	testTimerGauntletClockedCanLaunchPerformOneActionAndEnd \
	testTimerGauntletEnduranceCanLaunchPerformOneActionAndEnd \
	testPrimitiveCapstoneFastCanLaunchPerformOneActionAndEnd \
	testPrimitiveChipperCanLaunchPerformOneActionAndEnd \
	testPrimitiveIntervalsCanLaunchPerformOneActionAndEnd \
	testPrimitiveCarryCircuitCanLaunchPerformOneActionAndEnd \
	testPrimitiveStrengthDensityCanLaunchPerformOneActionAndEnd \
	testPrimitiveCapstoneSaveAndDoneRendersHistoryPrimitiveRows

WORKOUT_TYPE_UI_DATA_TESTS := \
	ExecutionWorkoutTypeMatrixDataTests

WORKOUT_TYPE_UI_EXPECTED_BUNDLES := $(shell expr $(words $(WORKOUT_TYPE_UI_DATA_TESTS)) + $(words $(WORKOUT_TYPE_UI_TESTS)))

EXECUTION_UI_TESTS := \
	testEndConfirmationOpensFromRest

SETTINGS_UI_TESTS := \
	testHealthArchiveControlsPersistThroughRelaunch

help:  ## Show this help
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*?##/ {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

setup:  ## One-time: install deps + pre-commit hooks
	uv sync --extra dev
	uv run pre-commit install --hook-type pre-commit --hook-type pre-push

dev:  ## Run the server with auto-reload (loads .env)
	uv run uvicorn workoutdb_server.main:app --reload

test: test-python test-swift test-app-packages  ## Run server, contract, schema, and Swift package tests

test-python:  ## Run Python tests (server + contract)
	uv run pytest

test-swift:  ## Run Swift schema package tests
	cd schema && swift test

test-core:  ## Run Core + Sync executable Swift package tests (CLT-compatible)
	cd app/Packages/Core/Foundation && swift run WorkoutCoreFoundationTests
	cd app/Packages/Core/Domain && swift run CoreDomainTests
	cd app/Packages/Core/Prescription && swift run CorePrescriptionTests
	cd app/Packages/Core/Autoreg && swift run CoreAutoregTests
	cd app/Packages/Core/Session && swift run CoreSessionTests
	cd app/Packages/Core/Telemetry && swift run CoreTelemetryTests
	cd app/Packages/Sync && swift run SyncTests

test-app-packages: test-core  ## Run every Swift package test target under app/Packages
	cd app/Packages/DesignSystem && swift run DesignSystemTests
	cd app/Packages/ExportProfile && swift test
	cd app/Packages/HealthArchiveExport && swift run HealthArchiveExportTests
	cd app/Packages/HealthKitBridge && swift run HealthKitBridgeTests
	cd app/Packages/Persistence && swift test
	cd app/Packages/WatchBridge && swift test
	cd app/Packages/WorkoutKitAdapter && swift test
	cd app/Packages/Features/Today && swift test
	cd app/Packages/Features/Execution && swift test
	cd app/Packages/Features/FirstRun && swift test
	cd app/Packages/Features/History && swift test
	cd app/Packages/Features/Settings && swift test
	cd app/Packages/Features/WatchFaces && swift test
	cd app/Packages/Shell && swift test

test-app-xcode: xcodegen  ## Build app target and run the generated iOS app compile/link smoke on a simulator
	xcodebuild test -project app/WorkoutDB.xcodeproj -scheme WorkoutDB \
	  -destination 'platform=iOS Simulator,name=$(IOS_SIMULATOR)' \
	  -configuration Debug CODE_SIGNING_ALLOWED=NO \
	  -only-testing:WorkoutDBTests

test-execution-ui: xcodegen  ## Run execution-focused XCUITests on a simulator
	mkdir -p "$(XCODE_RESULT_ROOT)"
	@for test_name in $(EXECUTION_UI_TESTS); do \
	  xcrun simctl shutdown "$(IOS_SIMULATOR)" >/dev/null 2>&1 || true; \
	  xcrun simctl boot "$(IOS_SIMULATOR)" >/dev/null 2>&1 || true; \
	  xcrun simctl bootstatus "$(IOS_SIMULATOR)" -b; \
	  xcrun simctl terminate "$(IOS_SIMULATOR)" com.ericfeunekes.WorkoutDB >/dev/null 2>&1 || true; \
	  xcodebuild test -project app/WorkoutDB.xcodeproj -scheme WorkoutDB \
	    -destination 'platform=iOS Simulator,name=$(IOS_SIMULATOR)' \
	    -configuration Debug CODE_SIGNING_ALLOWED=NO \
	    -resultBundlePath "$(XCODE_RESULT_ROOT)/$${test_name}.xcresult" \
	    -only-testing:WorkoutDBUITests/ExecutionEndConfirmationUITests/$${test_name} || exit $$?; \
	done

test-settings-ui: xcodegen  ## Run Settings-focused XCUITests on a simulator
	mkdir -p "$(XCODE_RESULT_ROOT)"
	@for test_name in $(SETTINGS_UI_TESTS); do \
	  xcrun simctl shutdown "$(IOS_SIMULATOR)" >/dev/null 2>&1 || true; \
	  xcrun simctl boot "$(IOS_SIMULATOR)" >/dev/null 2>&1 || true; \
	  xcrun simctl bootstatus "$(IOS_SIMULATOR)" -b; \
	  xcrun simctl terminate "$(IOS_SIMULATOR)" com.ericfeunekes.WorkoutDB >/dev/null 2>&1 || true; \
	  xcodebuild test -project app/WorkoutDB.xcodeproj -scheme WorkoutDB \
	    -destination 'platform=iOS Simulator,name=$(IOS_SIMULATOR)' \
	    -configuration Debug CODE_SIGNING_ALLOWED=NO \
	    -resultBundlePath "$(XCODE_RESULT_ROOT)/$${test_name}.xcresult" \
	    -only-testing:WorkoutDBUITests/SettingsHealthArchiveUITests/$${test_name} || exit $$?; \
	done

test-workout-type-ui: xcodegen  ## Run every timing mode and composed primitive execution XCUITest
	mkdir -p "$(XCODE_RESULT_ROOT)"
	@for test_name in $(WORKOUT_TYPE_UI_DATA_TESTS); do \
	  xcodebuild test -project app/WorkoutDB.xcodeproj -scheme WorkoutDB \
	    -destination 'platform=iOS Simulator,name=$(IOS_SIMULATOR)' \
	    -configuration Debug CODE_SIGNING_ALLOWED=NO \
	    -resultBundlePath "$(XCODE_RESULT_ROOT)/$${test_name}.xcresult" \
	    -only-testing:WorkoutDBUITests/$${test_name} || exit $$?; \
	done
	@for test_name in $(WORKOUT_TYPE_UI_TESTS); do \
	  xcrun simctl boot "$(IOS_SIMULATOR)" >/dev/null 2>&1 || true; \
	  xcrun simctl bootstatus "$(IOS_SIMULATOR)" -b; \
	  xcrun simctl terminate "$(IOS_SIMULATOR)" com.ericfeunekes.WorkoutDB >/dev/null 2>&1 || true; \
	  xcodebuild test -project app/WorkoutDB.xcodeproj -scheme WorkoutDB \
	    -destination 'platform=iOS Simulator,name=$(IOS_SIMULATOR)' \
	    -configuration Debug CODE_SIGNING_ALLOWED=NO \
	    -resultBundlePath "$(XCODE_RESULT_ROOT)/$${test_name}.xcresult" \
	    -only-testing:WorkoutDBUITests/ExecutionWorkoutTypeMatrixUITests/$${test_name} || exit $$?; \
	done
	@actual_bundles=$$(find "$(XCODE_RESULT_ROOT)" -maxdepth 1 -name '*.xcresult' | wc -l | tr -d ' '); \
	  if [ "$$actual_bundles" != "$(WORKOUT_TYPE_UI_EXPECTED_BUNDLES)" ]; then \
	    echo "Expected $(WORKOUT_TYPE_UI_EXPECTED_BUNDLES) workout-type result bundles under $(XCODE_RESULT_ROOT), found $$actual_bundles"; \
	    exit 1; \
	  fi

test-workout-type-ui-repeat: xcodegen  ## Repeat the full workout-type UI matrix to prove runner stability
	@for run_index in $$(seq 1 $(WORKOUT_TYPE_UI_REPEAT_COUNT)); do \
	  run_root="$(XCODE_RESULT_ROOT)/workout-type-run-$${run_index}"; \
	  echo "Workout-type UI repeat $$run_index/$(WORKOUT_TYPE_UI_REPEAT_COUNT): $$run_root"; \
	  $(MAKE) test-workout-type-ui XCODE_RESULT_ROOT="$$run_root" IOS_SIMULATOR="$(IOS_SIMULATOR)" || exit $$?; \
	done

test-tokenstore-keychain-ui: xcodegen  ## Run signed simulator proof for real TokenStore Keychain read/write/delete
	@mkdir -p "$(XCODE_RESULT_ROOT)"
	xcodebuild test -project app/WorkoutDB.xcodeproj -scheme WorkoutDB \
	  -destination 'platform=iOS Simulator,name=$(IOS_SIMULATOR)' \
	  -configuration Debug \
	  -resultBundlePath "$(XCODE_RESULT_ROOT)/TokenStoreKeychainBoundaryTests.xcresult" \
	  -only-testing:WorkoutDBKeychainTests

test-healthkit-ui: xcodegen  ## Run signed HealthKit archive/projection simulator proof
	@mkdir -p "$(XCODE_RESULT_ROOT)"
	xcodebuild build -project app/WorkoutDB.xcodeproj -scheme WorkoutDB \
	  -destination 'platform=iOS Simulator,name=$(IOS_SIMULATOR)' \
	  -configuration Debug \
	  -derivedDataPath "$(HEALTHKIT_PREFLIGHT_DERIVED_DATA)"
	@simulated_entitlements="$(HEALTHKIT_PREFLIGHT_DERIVED_DATA)/Build/Intermediates.noindex/WorkoutDB.build/Debug-iphonesimulator/WorkoutDB.build/WorkoutDB.app-Simulated.xcent"; if [ ! -f "$$simulated_entitlements" ]; then echo "HealthKit simulator preflight failed: Xcode did not emit WorkoutDB.app-Simulated.xcent."; exit 1; fi; if [ "$$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.healthkit' "$$simulated_entitlements" 2>/dev/null)" != "true" ]; then echo "HealthKit simulator preflight failed: WorkoutDB.app-Simulated.xcent does not include com.apple.developer.healthkit."; exit 1; fi
	xcodebuild test -project app/WorkoutDB.xcodeproj -scheme WorkoutDB \
	  -destination 'platform=iOS Simulator,name=$(IOS_SIMULATOR)' \
	  -configuration Debug \
	  -resultBundlePath "$(XCODE_RESULT_ROOT)/HealthKitAuthorizationUITests.xcresult" \
	  -only-testing:WorkoutDBUITests/HealthKitAuthorizationUITests

assert-healthkit-watch-sim-log:  ## Assert XcodeBuildMCP watch HealthKit probe log. Usage: make assert-healthkit-watch-sim-log PROBE_LOG=/path/log.txt
	@test -n "$(PROBE_LOG)" || { echo "usage: make assert-healthkit-watch-sim-log PROBE_LOG=/path/to/xcodebuildmcp-runtime.log"; exit 2; }
	uv run python app/Integration/healthkit_watch_sim/assert_live_workout_probe.py "$(PROBE_LOG)"

test-healthkit-watch-sim:  ## Assert the latest XcodeBuildMCP watch HealthKit live-workout probe log
	uv run python app/Integration/healthkit_watch_sim/assert_latest_live_workout_probe.py

test-sync-real-http:  ## Run FastAPI + SQLite + Swift URLSession primitive sync probe
	uv run pytest app/Integration/sync_real_http/test_sync_real_http.py

check-app: test-app-packages test-app-xcode test-execution-ui  ## Current local app pre-QA gate

lint:  ## ruff check + import-linter
	uv run ruff check .
	uv run lint-imports

format:  ## ruff format
	uv run ruff format .

check: lint  ## Server/schema verification (ruff format --check + ruff check + lint-imports + pytest + schema swift test)
	uv run ruff format --check .
	uv run pytest
	cd schema && swift test

pre-qa: check test-sync-real-http check-app  ## Current behavior pre-QA proof gate before entering docs/QA.md flows

regen-schema:  ## Regenerate schema/openapi.json from the live FastAPI app
	WORKOUTDB_BEARER_TOKEN=dummy WORKOUTDB_DB_PATH=/tmp/dummy.db \
	  uv run python -c "import json; from workoutdb_server.main import app; print(json.dumps(app.openapi(), indent=2))" \
	  > schema/openapi.json

xcodegen:  ## Regenerate app/WorkoutDB.xcodeproj from app/project.yml
	@if PATH="$(XCODEGEN_PATH)" command -v xcodegen >/dev/null 2>&1; then \
	  cd app && PATH="$(XCODEGEN_PATH)" xcodegen generate; \
	elif [ -f app/WorkoutDB.xcodeproj/project.pbxproj ] && [ app/WorkoutDB.xcodeproj/project.pbxproj -nt app/project.yml ]; then \
	  echo "xcodegen: skipped (not installed; using existing app/WorkoutDB.xcodeproj)"; \
	else \
	  echo "xcodegen: not installed and app/WorkoutDB.xcodeproj is missing or stale"; exit 127; \
	fi

xcode-mcp-tools:  ## Verify global XcodeBuildMCP exposes tools
	PATH="$(XCODE_MCP_PATH)" xcodebuildmcp tools

qa-ready: xcode-mcp-tools  ## Verify QA tool availability before simulator/device QA

qa-runtime-ready: qa-ready  ## Verify local tools used by ETTrace/memgraph runtime proof
	@command -v leaks >/dev/null 2>&1 || { echo "leaks not found"; exit 127; }
	@xcrun xctrace version >/dev/null
	@xcrun simctl help >/dev/null
	@mkdir -p scratch/qa-runs

release-bump-build:  ## Increment app/project.yml CFBundleVersion. Override BUILD= for explicit value.
	uv run python deploy/release/testflight.py bump-build $(if $(BUILD),--to $(BUILD),)

release-preflight:  ## Verify TestFlight release can run non-interactively for RELEASE_REF
	uv run python deploy/release/testflight.py $(RELEASE_ARGS) preflight $(RELEASE_PREFLIGHT_ARGS) --release-ref "$(RELEASE_REF)"

release-testflight:  ## Archive, export, upload, and assign committed RELEASE_REF to TestFlight
	uv run python deploy/release/testflight.py $(RELEASE_ARGS) release --release-ref "$(RELEASE_REF)" $(RELEASE_GATE_ARGS)

release-status:  ## Read back current app/project.yml build status from App Store Connect
	uv run python deploy/release/testflight.py $(RELEASE_ARGS) status $(if $(RELEASE_VERSION),--version "$(RELEASE_VERSION)",) $(if $(RELEASE_BUILD),--build "$(RELEASE_BUILD)",)

release-resume:  ## Resume TestFlight assignment/readiness from MANIFEST=/path/manifest.json
	@test -n "$(MANIFEST)" || { echo "usage: make release-resume MANIFEST=/path/to/manifest.json"; exit 2; }
	uv run python deploy/release/testflight.py $(RELEASE_ARGS) resume --manifest "$(MANIFEST)"

clean:  ## Remove .pytest_cache, .ruff_cache, schema/.build, app/.build, Xcode DerivedData
	rm -rf .pytest_cache .ruff_cache schema/.build
	rm -rf app/Packages/*/.build app/Packages/Core/*/.build
	rm -rf app/Packages/Features/*/.build
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
