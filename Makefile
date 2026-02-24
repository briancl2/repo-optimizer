.PHONY: review optimize patch-check test validate help install-hooks check work work-close spec-init

TARGET ?= .
AUDIT ?= audit_output
OUTPUT_DIR ?= optimizer_output
PATCH ?= false

help:
	@echo "repo-optimizer -- Concrete optimization patches for any repository"
	@echo ""
	@echo "Targets:"
	@echo "  make optimize TARGET=<path> AUDIT=<dir>  Run optimizer (report-only)"
	@echo "  make optimize TARGET=<path> AUDIT=<dir> PATCH=true  With patches"
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

patch-check:
	@bash scripts/validate-patches.sh "$(TARGET)" "$(OUTPUT_DIR)/PATCH_PACK"

test:
	@echo "=== Running optimizer test suite ==="
	@bash tests/test-critic-rejects.sh
	@bash tests/test-patches-apply.sh
	@bash tests/test-preflight-tiers.sh
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

spec-init:
	@if [ -f .specify/scripts/bash/create-new-feature.sh ]; then \
		bash .specify/scripts/bash/create-new-feature.sh "$(DESC)"; \
	else \
		echo "ERROR: spec-kit scripts not found in .specify/"; exit 1; \
	fi
