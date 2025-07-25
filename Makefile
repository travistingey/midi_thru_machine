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

test:
	LUA_PATH='./?.lua;./lib/?.lua;test/.test/stubs/?.lua;test/spec/?.lua;;' busted test/spec

test-local:
	LUA_PATH='./?.lua;./lib/?.lua;test/.test/stubs/?.lua;test/spec/?.lua;;' busted test/spec/e2e_spec.lua

# Test on Norns using system shell (Lua 5.1) - for compatibility testing
test-norns-shell:
	sshpass -p "$(NORNS_PASS)" ssh $(SSH_OPTS) "$(NORNS_HOST)" "cd $(NORNS_PATH) && LUA_PATH='./?.lua;./lib/?.lua;test/spec/?.lua;;' busted -o plain test/spec"

# Test on Norns using actual Norns runtime (Lua 5.3) - for real environment testing
test-norns-runtime:
	./scripts/run-test test/norns_runtime_spec.lua

# Test on Norns using busted in the actual runtime
test-norns-busted:
	./scripts/run-test test/norns_busted_spec.lua

# Test on Norns using the old approach (deprecated)
test-norns-legacy:
	sshpass -p "$(NORNS_PASS)" ssh $(SSH_OPTS) "$(NORNS_HOST)" "cd $(NORNS_PATH) && echo 'dofile(\"test/run_norns_test.lua\")' | norns"

# Default Norns test (use runtime for comprehensive testing)
test-norns: test-norns-runtime

# Comprehensive testing across all environments
test-all: test test-norns-shell test-norns-runtime

ci: lint test

deploy:
	sshpass -p "$(NORNS_PASS)" rsync -e "ssh $(SSH_OPTS)" -av --exclude='.git' ./ "$(NORNS_HOST):$(NORNS_PATH)"

deploy-and-test: deploy test-norns-runtime

# Setup Norns device for testing (run once)
setup-norns:
	sshpass -p "$(NORNS_PASS)" ssh $(SSH_OPTS) "$(NORNS_HOST)" "sudo apt-get update && sudo apt-get install -y socat git luarocks lua5.1-dev && sudo luarocks install busted"

.PHONY: install lint test test-local test-norns test-norns-shell test-norns-runtime test-norns-busted test-norns-legacy test-all ci deploy deploy-and-test setup-norns
