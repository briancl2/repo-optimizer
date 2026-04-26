.PHONY: review optimize transfer-oracle benchmark-optimization-workloads normalize-agent-run-receipts build-live-paired-corpus collect-live-agent-receipts patch-check test validate help install-hooks check work work-close health spec-init

TARGET ?= .
AUDIT ?= audit_output
OUTPUT_DIR ?= optimizer_output
PATCH ?= false
DECISIONS ?=
CAPABILITY_FAMILY ?=
HOTSPOT_ID ?=
CORPUS ?=
MODE ?= retained-replay
FIXTURES ?=
RECEIPTS ?=
ADAPTER ?=
MODEL ?=
REPETITIONS ?= 5
COMMAND_TEMPLATE ?=

help:
	@echo "repo-optimizer -- Concrete optimization patches for any repository"
	@echo ""
	@echo "Targets:"
	@echo "  make optimize TARGET=<path> AUDIT=<dir>  Run optimizer (report-only)"
	@echo "  make optimize TARGET=<path> AUDIT=<dir> PATCH=true  With patches"
	@echo "  make transfer-oracle DECISIONS=<path>    Evaluate bounded advisory decisions (optional: OUTPUT_DIR, CAPABILITY_FAMILY, HOTSPOT_ID)"
	@echo "  make benchmark-optimization-workloads CORPUS=<path> OUTPUT_DIR=<dir> MODE=<deterministic|retained-replay|live-paired>"
	@echo "  make normalize-agent-run-receipts RECEIPTS=<raw> OUTPUT_DIR=<dir>  Normalize Codex/Copilot/VS Code/generic evidence"
	@echo "  make build-live-paired-corpus FIXTURES=<path> RECEIPTS=<path> OUTPUT_DIR=<dir>  Build provider-neutral live corpus"
	@echo "  make collect-live-agent-receipts FIXTURES=<path> ADAPTER=<codex|copilot|generic> OUTPUT_DIR=<dir>  Collect live receipts"
	@echo "  make patch-check                         Validate existing patches"
	@echo "  make test                                Run all tests"
	@echo "  make validate                            Validate bundle integrity"
	@echo "  make review                              Code review staged changes"
	@echo "  make check                               Pre-commit gate (shellcheck + inventory)"
	@echo "  make work DESC=\"...\"                     Open work contract"
	@echo "  make work-close WORK=<dir>               Close work contract"
	@echo "  make spec-init DESC=\"...\"               Create new spec"
	@echo "  make install-hooks                       Install git hooks"

review:
	@bash .agents/skills/reviewing-code-locally/scripts/local_review.sh

optimize:
	@echo "=== repo-optimizer ==="
	@mkdir -p $(OUTPUT_DIR)
	@if [ "$(PATCH)" = "true" ]; then \
		bash scripts/repo-optimizer.sh "$(TARGET)" "$(AUDIT)" "$(OUTPUT_DIR)" --patch; \
	else \
		bash scripts/repo-optimizer.sh "$(TARGET)" "$(AUDIT)" "$(OUTPUT_DIR)"; \
	fi
	@echo "=== Optimization complete. Artifacts in $(OUTPUT_DIR)/ ==="

transfer-oracle:
	@echo "=== repo-optimizer: Advisory Transfer Oracle ==="
	@test -n "$(DECISIONS)" || { echo "ERROR: DECISIONS=<path> required"; exit 1; }
	@mkdir -p "$(OUTPUT_DIR)"
	@python3 scripts/evaluate-advisory-transfer.py \
		--decisions "$(DECISIONS)" \
		--output "$(OUTPUT_DIR)/TRANSFER_ORACLE_RECEIPT.json" \
		--capability-family "$(CAPABILITY_FAMILY)" \
		--hotspot-id "$(HOTSPOT_ID)"
	@echo "=== Transfer oracle receipt written to $(OUTPUT_DIR)/TRANSFER_ORACLE_RECEIPT.json ==="

benchmark-optimization-workloads:
	@echo "=== repo-optimizer: Prompt/Context Benchmark Harness ==="
	@test -n "$(CORPUS)" || { echo "ERROR: CORPUS=<path> required"; exit 1; }
	@mkdir -p "$(OUTPUT_DIR)"
	@python3 scripts/benchmark-optimization-workloads.py \
		--corpus "$(CORPUS)" \
		--output-dir "$(OUTPUT_DIR)" \
		--mode "$(MODE)"
	@echo "=== Benchmark artifacts written to $(OUTPUT_DIR)/ ==="

normalize-agent-run-receipts:
	@echo "=== repo-optimizer: Normalize Agent Run Receipts ==="
	@test -n "$(RECEIPTS)" || { echo "ERROR: RECEIPTS=<raw receipt/session path> required"; exit 1; }
	@mkdir -p "$(OUTPUT_DIR)"
	@python3 scripts/normalize-agent-run-receipts.py \
		--input "$(RECEIPTS)" \
		--output "$(OUTPUT_DIR)/AGENT_RUN_RECEIPTS.json"
	@echo "=== Normalized receipts written to $(OUTPUT_DIR)/AGENT_RUN_RECEIPTS.json ==="

build-live-paired-corpus:
	@echo "=== repo-optimizer: Build Provider-Neutral Live-Paired Corpus ==="
	@test -n "$(FIXTURES)" || { echo "ERROR: FIXTURES=<path> required"; exit 1; }
	@test -n "$(RECEIPTS)" || { echo "ERROR: RECEIPTS=<AGENT_RUN_RECEIPTS path> required"; exit 1; }
	@mkdir -p "$(OUTPUT_DIR)"
	@python3 scripts/build-live-paired-corpus.py \
		--fixtures "$(FIXTURES)" \
		--receipts "$(RECEIPTS)" \
		--output "$(OUTPUT_DIR)/OPTIMIZATION_BENCHMARK_CORPUS.json"
	@echo "=== Live-paired corpus written to $(OUTPUT_DIR)/OPTIMIZATION_BENCHMARK_CORPUS.json ==="

collect-live-agent-receipts:
	@echo "=== repo-optimizer: Collect Live Agent Receipts ==="
	@test -n "$(FIXTURES)" || { echo "ERROR: FIXTURES=<path> required"; exit 1; }
	@test -n "$(ADAPTER)" || { echo "ERROR: ADAPTER=<codex|copilot|generic> required"; exit 1; }
	@mkdir -p "$(OUTPUT_DIR)"
	@python3 scripts/run-live-agent-benchmark.py \
		--fixtures "$(FIXTURES)" \
		--output "$(OUTPUT_DIR)/AGENT_RUN_RECEIPTS.json" \
		--adapter "$(ADAPTER)" \
		--model "$(MODEL)" \
		--repetitions "$(REPETITIONS)" $(if $(COMMAND_TEMPLATE),--command-template "$(COMMAND_TEMPLATE)",)
	@echo "=== Live receipts written to $(OUTPUT_DIR)/AGENT_RUN_RECEIPTS.json ==="

patch-check:
	@bash scripts/validate-patches.sh "$(TARGET)" "$(OUTPUT_DIR)/PATCH_PACK"

test:
	@echo "=== Running optimizer test suite ==="
	@bash tests/test-critic-rejects.sh
	@bash tests/test-discovery-payload-capture.sh
	@bash tests/test-phase-output-classifier.sh
	@bash tests/test-transfer-oracle-consumer.sh
	@bash tests/test-patches-apply.sh
	@bash tests/test-preflight-tiers.sh
	@bash tests/test-optimization-benchmark-harness.sh
	@bash tests/test-agent-run-receipts.sh
	@bash tests/test-self-management.sh
	@bash tests/test-grader-golden.sh
	@echo ""
	@echo "=== All tests passed ==="

validate:
	@bash .agents/skills/bundle-integrity/scripts/validate-bundle.sh $(OUTPUT_DIR)

install-hooks:
	@if [ -f ~/repos/repo-agent-core/scripts/install-hooks.sh ]; then \
		bash ~/repos/repo-agent-core/scripts/install-hooks.sh .; \
	else \
		cp scripts/pre-commit-hook.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit && echo "Installed pre-commit hook"; \
	fi

check:
	@bash scripts/check.sh

work:
	@bash scripts/work-init.sh "$(DESC)"

work-close:
	@bash scripts/work-close.sh "$(WORK)"

health:
	@echo "=== Operations Health (last 5 entries) ==="
	@if [ -f work/OPERATIONS_LEDGER.jsonl ]; then \
		tail -5 work/OPERATIONS_LEDGER.jsonl | python3 -c "import sys,json; entries=[json.loads(l) for l in sys.stdin]; print(f'Entries: {len(entries)}'); [print(f'  {e.get(\"timestamp\",\"?\")}: {e.get(\"event_type\",\"?\")} score={e.get(\"data\",{}).get(\"composite_score\",\"?\")}'  ) for e in entries]" 2>/dev/null || echo "  (parse error)"; \
	else \
		echo "  No operations ledger yet (work/OPERATIONS_LEDGER.jsonl)"; \
	fi

spec-init:
	@if [ -f .specify/scripts/bash/create-new-feature.sh ]; then \
		bash .specify/scripts/bash/create-new-feature.sh "$(DESC)"; \
	else \
		echo "ERROR: spec-kit scripts not found in .specify/"; exit 1; \
	fi
