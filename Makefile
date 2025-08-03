LUA=lua
LUAROCKS=luarocks
PI_HOST=we@norns.local
SSH_KEY=~/.ssh/norns_key
SCRIPT_NAME=Foobar
SCRIPT_PATH=/home/we/dust/code/$(SCRIPT_NAME)/$(SCRIPT_NAME).lua

install:
	brew install lua@5.3 || true
	brew install luarocks || true
	$(LUAROCKS) install busted || true
	$(LUAROCKS) install luacheck || true
	brew install fswatch || true

lint:
	luacheck src || true 

ci: lint

norns:
	ssh -i $(SSH_KEY) $(PI_HOST)

deploy:
	rsync -av --delete -e "ssh -i $(SSH_KEY)" src/ $(PI_HOST):~/dust/code/$(SCRIPT_NAME)/

reload:
	@echo "Reloading script on Norns..."
	node scripts/send-to-norns.js "for script,value in pairs(package.loaded) do if string.match(script, '$(SCRIPT_NAME)') then package.loaded[script] = nil end end; norns.script.load('$(SCRIPT_PATH)')"

push:
	make deploy
	make reload

test:
	make deploy-tests
	make run-tests

# Deploy and run tests on Norns
TEST_SCRIPT_NAME=$(SCRIPT_NAME)Tests
TEST_PATH=/home/we/dust/code/$(TEST_SCRIPT_NAME)/$(TEST_SCRIPT_NAME).lua

deploy-tests:
	rsync -av --delete -e "ssh -i $(SSH_KEY)" test/ $(PI_HOST):~/dust/code/$(TEST_SCRIPT_NAME)/

run-tests:
	@echo "Running test suite on Norns..."
	node scripts/send-to-norns.js "for script,value in pairs(package.loaded) do if string.match(script, '$(TEST_SCRIPT_NAME)') then package.loaded[script] = nil end end; norns.script.load('$(TEST_PATH)')"

watch:
	@echo "Watching for changes in src/ and .test/..."
	@echo "Press Ctrl+C to stop"
	fswatch -o src/ | xargs -n1 -I{} sh -c 'echo "Change detected at $$(date)"; make push'

.PHONY: install lint test ci deploy reload deploy-tests run-tests test-norns watch
