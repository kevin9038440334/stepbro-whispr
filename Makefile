.PHONY: build run install dmg test clean

APP = build/stepbro whispr.app

build:
	@./scripts/build.sh

run: build
	@pkill -x StepbroWhispr || true
	@open "$(APP)"

install: build
	@pkill -x StepbroWhispr || true
	@rm -rf "/Applications/stepbro whispr.app"
	@cp -R "$(APP)" /Applications/
	@open "/Applications/stepbro whispr.app"
	@echo "Instalado en /Applications"

dmg:
	@./scripts/make-dmg.sh

test:
	@swift test --build-system native

clean:
	@rm -rf .build build
