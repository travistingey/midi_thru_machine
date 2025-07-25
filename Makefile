LUA=lua
LUAROCKS=luarocks

install:
	brew install lua@5.3 || true
	brew install luarocks || true
	$(LUAROCKS) install busted || true
	$(LUAROCKS) install luacheck || true

lint:
	luacheck Foobar.lua lib spec || true

test:
	LUA_PATH='./?.lua;./lib/?.lua;.test/stubs/?.lua;;' busted

ci: lint test

deploy:
	rsync -av --exclude='.git' ./ $(PI_HOST):~/dust/code/Foobar

.PHONY: install lint test ci deploy
