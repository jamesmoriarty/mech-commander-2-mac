# MechCommander 2 for macOS — convenience targets.
# Build logic lives in scripts/*.sh (bash, not make).

SCRIPTS := scripts
BREW_DEPS := cmake sdl2-compat sdl2_mixer sdl2_ttf glew

.PHONY: help deps native run dist dist-no-data clean

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) \
		| awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

deps: ## Install Homebrew build dependencies
	brew install $(BREW_DEPS)

native: ## Build the native engine + process game data (build/native)
	@$(SCRIPTS)/build-native-macos.sh

run: ## Build if needed, then launch the game
	@$(SCRIPTS)/run-native-macos.sh

dist: ## Build dist/MechCommander2.app, zip, and mc2-data.tar.gz
	@$(SCRIPTS)/build-dist-macos.sh

dist-no-data: ## Same as dist but skip the game-data archive
	@SKIP_DATA_ARCHIVE=1 $(SCRIPTS)/build-dist-macos.sh

clean: ## Remove build/ and dist/ outputs
	rm -rf build dist
