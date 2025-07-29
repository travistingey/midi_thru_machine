LUA=lua
LUAROCKS=luarocks
PI_HOST=we@norns.local
SSH_KEY=~/.ssh/norns_key

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
farts:
	ssh -T -i $(SSH_KEY) $(PI_HOST) 'matron' <<'EOF'
	print("hello from make")
	norns.script.load(norns.state.script)
	EOF
deploy:
	rsync -av --delete -e "ssh -i $(SSH_KEY)" src/ $(PI_HOST):~/dust/code/Foobar/

watch:
	@echo "Watching for changes in src/ and .test/..."
	@echo "Press Ctrl+C to stop"
	fswatch -o src/ .test/ | xargs -n1 -I{} sh -c 'echo "Change detected at $$(date)"; make ci && make deploy'

.PHONY: install lint test ci deploy watch
