.PHONY: build dmg clean setup

setup:
	./build-whisper.sh
	./scripts/generate-engine-info.sh
	xcodegen generate

build: setup
	xcodebuild -scheme Whispeur -configuration Release build SYMROOT="$(PWD)/build"

dmg: build
	mkdir -p /tmp/whispeur-dmg-src && rm -rf /tmp/whispeur-dmg-src/*
	cp -r build/Release/Whispeur.app /tmp/whispeur-dmg-src/
	ln -s /Applications /tmp/whispeur-dmg-src/Applications
	rm -f Whispeur.dmg
	hdiutil create -volname "Whispeur" -srcfolder /tmp/whispeur-dmg-src -ov -format UDZO Whispeur.dmg
	rm -rf /tmp/whispeur-dmg-src

clean:
	rm -rf build
	rm -rf build-whisper
	rm -f Whispeur.dmg
	rm -rf Whispeur.xcodeproj
