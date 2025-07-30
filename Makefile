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
	luacheck src .test/spec || true

test:
	LUA_PATH='./src/?.lua;./src/lib/?.lua;.test/stubs/?.lua;;' busted .test/spec

ci: lint test

norns:
	ssh -i $(SSH_KEY) $(PI_HOST)

deploy:
	rsync -av --delete -e "ssh -i $(SSH_KEY)" src/ $(PI_HOST):~/dust/code/$(SCRIPT_NAME)/

reload:
	@echo "Reloading script on Norns..."
	node scripts/send-to-norns.js "for script,value in pairs(package.loaded) do if string.match(script, '$(SCRIPT_NAME)') then package.loaded[script] = nil end end; norns.script.load('$(SCRIPT_PATH)')"

# Deploy and run tests on Norns
TEST_SCRIPT_NAME=$(SCRIPT_NAME)Tests
TEST_PATH=/home/we/dust/code/$(TEST_SCRIPT_NAME)/$(TEST_SCRIPT_NAME).lua

vendor-busted:
	@echo "Vendoring busted + dependencies into test/vendor…"
	# Busted
	@if [ ! -d test/vendor/busted ]; then \
		git clone --depth 1 https://github.com/Olivine-Labs/busted.git test/vendor/busted; \
	else \
		cd test/vendor/busted && git pull --depth 1; \
	fi
	# Penlight (pl.*)
	@if [ ! -d test/vendor/penlight ]; then \
		git clone --depth 1 https://github.com/lunarmodules/Penlight.git test/vendor/penlight; \
	else \
		cd test/vendor/penlight && git pull --depth 1; \
	fi
	# Luassert
	@if [ ! -d test/vendor/luassert ]; then \
		git clone --depth 1 https://github.com/lunarmodules/luassert.git test/vendor/luassert; \
	else \
		cd test/vendor/luassert && git pull --depth 1; \
	fi
	# Say (string i18n util required by luassert)
	@if [ ! -d test/vendor/say ]; then \
		git clone --depth 1 https://github.com/Olivine-Labs/say.git test/vendor/say; \
	else \
		cd test/vendor/say && git pull --depth 1; \
	fi
	# lua-term (terminal colour utils) – optional but nice
	@if [ ! -d test/vendor/lua-term ]; then \
		git clone --depth 1 https://github.com/hoelzro/lua-term.git test/vendor/lua-term; \
	else \
		cd test/vendor/lua-term && git pull --depth 1; \
	fi

deploy-tests: vendor-busted
	rsync -av --delete -e "ssh -i $(SSH_KEY)" test/ $(PI_HOST):~/dust/code/$(TEST_SCRIPT_NAME)/

run-tests:
	@echo "Running test suite on Norns..."
	node scripts/send-to-norns.js "for script,value in pairs(package.loaded) do if string.match(script, '$(TEST_SCRIPT_NAME)') then package.loaded[script] = nil end end; norns.script.load('$(TEST_PATH)')"

test-norns: deploy-tests run-tests

watch:
	@echo "Watching for changes in src/ and .test/..."
	@echo "Press Ctrl+C to stop"
	fswatch -o src/ | xargs -n1 -I{} sh -c 'echo "Change detected at $$(date)"; make lint && make deploy && make reload'

.PHONY: install lint test ci deploy reload vendor-busted deploy-tests run-tests test-norns watch
