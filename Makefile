.PHONY: help project build test install run hooks icons fixtures screenshots clean

DERIVED := build/DerivedData
APP     := $(DERIVED)/Build/Products/Release/Salon.app
XCB     := xcodebuild -project Salon.xcodeproj -scheme Salon -destination 'platform=macOS' -derivedDataPath $(DERIVED)

help:
	@echo "make install      Build a Release copy and install it in /Applications"
	@echo "make test         Run the unit tests (fixtures only, no network)"
	@echo "make build        Debug build"
	@echo "make project      Regenerate Salon.xcodeproj from project.yml"
	@echo "make hooks        Install the gitleaks pre-commit hook"
	@echo "make fixtures     Re-record API fixtures (live network, then scrubbed)"
	@echo "make icons        Re-render the app icon PNGs"
	@echo "make screenshots  Re-render README screenshots (debug build, sandboxed data)"

project:
	@command -v xcodegen >/dev/null || { echo "Install XcodeGen: brew install xcodegen"; exit 1; }
	xcodegen generate --quiet

build: project
	$(XCB) -configuration Debug build

test: project
	$(XCB) test

install: project
	$(XCB) -configuration Release build
	-pkill -x Salon
	rm -rf /Applications/Salon.app
	cp -R "$(APP)" /Applications/Salon.app
	open /Applications/Salon.app
	@echo "Salon is installed. Look for the frame icon in the menu bar."

run: build
	open "$(DERIVED)/Build/Products/Debug/Salon.app"

hooks:
	scripts/install-hooks.sh

icons:
	swift scripts/render-icons.swift

fixtures:
	scripts/record-fixtures.sh

screenshots: build
	mkdir -p build/screenshots
	"$(DERIVED)/Build/Products/Debug/Salon.app/Contents/MacOS/Salon" --screenshots "$(CURDIR)/build/screenshots"
	@echo "Screenshots in build/screenshots; copy the ones you want to docs/screenshots."

clean:
	rm -rf build Salon.xcodeproj
