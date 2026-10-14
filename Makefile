.PHONY: lint validate-local lint-catalog

lint: ## Run all local validations (always runs both, reports combined result)
	@rc=0; \
	 bash scripts/validate-local.sh --quiet   || rc=1; \
	 bash scripts/lint-catalog.sh --quiet     || rc=1; \
	 [ $$rc -eq 0 ] && echo "" && echo "OK: all checks passed." || echo ""; \
	 exit $$rc

validate-local: ## Validate listing metadata (v*/metadata.yaml, profile.yaml) — mirrors CI schema checks
	@bash scripts/validate-local.sh

lint-catalog: ## Validate catalog import contract (catalog/catalog.yaml, schema.json) against import.sh expectations
	@bash scripts/lint-catalog.sh
