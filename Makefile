LUA=lua
LUAROCKS=luarocks

# Load environment variables if .env exists
ifneq (,$(wildcard .env))
    include .env
    export
endif

# Set defaults
NORNS_HOST ?= we@norns.local
NORNS_PASS ?= sleep
SSH_OPTS ?= -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
NORNS_PATH ?= ~/dust/code/Foobar

install:
	brew install lua@5.3 || true
	brew install luarocks || true
	brew install sshpass || true
	$(LUAROCKS) install busted || true
	$(LUAROCKS) install luacheck || true

lint:
	luacheck Foobar.lua lib test || true

test:`

deploy:
	sshpass -p "$(NORNS_PASS)" rsync -e "ssh $(SSH_OPTS)" -av --exclude='.git' ./ "$(NORNS_HOST):$(NORNS_PATH)"

# ------------------------------------------------------------------
# Norns helpers
# ------------------------------------------------------------------
deploy-tests:
	sshpass -p "$(NORNS_PASS)" rsync -e "ssh $(SSH_OPTS)" -av ./test "$(NORNS_HOST):$(NORNS_PATH)"

test-norns-shell:
	@echo "Opening interactive shell on $(NORNS_HOST) – when it opens:"
	@echo "  1) run:  matron"
	@echo "  2) then: dofile('$(NORNS_PATH)/test/run_norns_test.lua')"
	sshpass -p "$(NORNS_PASS)" ssh $(SSH_OPTS) "$(NORNS_HOST)"

deploy-and-test: deploy deploy-tests
	@echo "============================================================="
	@echo "Code + tests copied to $(NORNS_HOST):$(NORNS_PATH)"
	@echo "Now SSH in and run the suite:"
	@echo "  make test-norns-shell"
	@echo "============================================================="

.PHONY: install lint test test-local ci deploy deploy-tests deploy-and-test test-norns-shell
