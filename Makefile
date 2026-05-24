# SPDX-License-Identifier: GPL-3.0-only
#
# pkg-framework Makefile. Mirrors CI locally so contributors can prove
# the gate before pushing.
#
# Targets:
#   make help          list targets (default)
#   make doctor        environment preflight
#   make test          run the unit suite
#   make smoke         end-to-end onboarding round trip
#   make lint          all linters (shell + voice + docs)
#   make lint-shell    shellcheck (warning severity)
#   make lint-voice    em-dash gate (LOU_VOICE.md)
#   make lint-docs     basic markdown sanity
#   make ci            everything CI runs

.DEFAULT_GOAL := help

SHELL := bash
SHELLCHECK ?= shellcheck

# Files under shellcheck. Keep this in sync with the CI workflow.
SHELL_FILES := \
	bin/pkg-framework \
	install.sh \
	lib/framework.sh \
	lib/layout-check.sh \
	lib/input-tests.sh \
	tests/run_tests.sh \
	tests/_assert.sh \
	tests/_TEMPLATE.sh \
	$(wildcard tests/unit/test_*.sh) \
	$(wildcard tests/smoke/test_*.sh)

# Files under em-dash gate. Markdown + scripts. Excludes LICENSE (which
# is verbatim GPL-3.0 and may contain dashes inside legal prose).
VOICE_FILES := \
	README.md \
	CHANGELOG.md \
	COPYRIGHT \
	SECURITY.md \
	$(wildcard docs/*.md) \
	$(wildcard tests/*.md) \
	$(SHELL_FILES)

help:
	@awk '/^[a-zA-Z_-]+:/ && /##/ { sub(/:.*##/, "\t"); print }' $(MAKEFILE_LIST)

doctor: ## environment preflight
	@./bin/pkg-framework doctor

test: ## run the unit suite
	@./tests/run_tests.sh

smoke: ## end-to-end smoke (onboarding + package build)
	@for t in $(sort $(wildcard tests/smoke/test_*.sh)); do \
		printf '\n=== %s ===\n' "$$t"; \
		bash "$$t" || exit 1; \
	done

lint: lint-shell lint-voice lint-docs ## all linters

lint-shell: ## shellcheck (warning severity; SC2016 info findings are intentional)
	@$(SHELLCHECK) --severity=warning -x $(SHELL_FILES)
	@printf 'shellcheck: clean\n'

lint-voice: ## em-dash gate (LOU_VOICE.md: zero em-dashes in added content)
	@if grep -lF '—' $(VOICE_FILES) 2>/dev/null | grep -q .; then \
		printf 'em-dash gate: FAIL\n' >&2; \
		grep -nHF '—' $(VOICE_FILES) >&2 || true; \
		exit 1; \
	fi; \
	printf 'em-dash gate: clean\n'

lint-docs: ## basic markdown sanity (no broken local link targets)
	@bad=0; \
	for f in $(filter %.md,$(VOICE_FILES)); do \
		dir=$$(dirname "$$f"); \
		while IFS= read -r ref; do \
			[ -n "$$ref" ] || continue; \
			target="$$dir/$$ref"; \
			[ -e "$$target" ] || { printf 'broken link in %s: %s (resolved to %s)\n' "$$f" "$$ref" "$$target" >&2; bad=$$((bad+1)); }; \
		done < <(grep -oE '\]\([^)#]+\.md[^)]*\)' "$$f" | sed -E 's/^\]\(([^)#]+)(#[^)]*)?\)/\1/'); \
	done; \
	[ "$$bad" -eq 0 ] || exit 1; \
	printf 'docs: link targets clean\n'

ci: lint test smoke ## everything CI runs

.PHONY: help doctor test smoke lint lint-shell lint-voice lint-docs ci
