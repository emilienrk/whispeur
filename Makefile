.PHONY: build dmg clean setup sparkle-tools release

release: sparkle-tools
	./scripts/release.sh $(VERSION)

SPARKLE_VERSION = 2.6.4

sparkle-tools: tools/sparkle/bin/generate_keys

tools/sparkle/bin/generate_keys:
	mkdir -p tools/sparkle
	curl -L -o /tmp/sparkle.tar.xz https://github.com/sparkle-project/Sparkle/releases/download/$(SPARKLE_VERSION)/Sparkle-$(SPARKLE_VERSION).tar.xz
	tar -xJf /tmp/sparkle.tar.xz -C tools/sparkle

setup:
	./build-whisper.sh
	./scripts/generate-engine-info.sh
	xcodegen generate

build: setup
	xcodebuild -scheme Whispeur -configuration Release build -derivedDataPath "$(PWD)/build/DerivedData"

dmg: build
	./scripts/make-dmg.sh

clean:
	rm -rf build
	rm -rf build-whisper
	rm -f Whispeur.dmg
	rm -rf Whispeur.xcodeproj
