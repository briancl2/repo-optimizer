.PHONY: review optimize test

TARGET ?= .
AUDIT ?= audit_output/SCORECARD.json

review:
	@bash .agents/skills/reviewing-code-locally/scripts/local_review.sh

optimize:
	@echo "Running optimizer on $(TARGET) with audit $(AUDIT)..."
	@echo "TODO: Wire up optimizer orchestrator"

test:
	@echo "Running tests..."
	@echo "TODO: AT-3 (valid patches), AT-4 (Mode A), AT-5 (Mode B), AT-10 (independence)"
