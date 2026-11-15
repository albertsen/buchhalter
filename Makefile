APP        := build/Buchhalter.app
BIN        := .build/release/buchhalter
CATALOG    := Resources/Localizable.xcstrings
INSTALLED  := /Applications/Buchhalter.app
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
XCSTRINGSTOOL := xcrun xcstringstool
SOURCES    := $(shell find Sources -name '*.swift') Package.swift

.DEFAULT_GOAL := build

.PHONY: build app install test strings clean

# Rebuilt only when a source file is newer than the binary.
$(BIN): $(SOURCES)
	swift build -c release

build: $(BIN)

# The binary, Info.plist and the compiled catalog (en.lproj, de.lproj),
# ad-hoc signed. Texts live in the main bundle, so SwiftUI and the core find them.
app: $(BIN) $(CATALOG) Resources/Info.plist
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN) $(APP)/Contents/MacOS/Buchhalter
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	$(XCSTRINGSTOOL) compile $(CATALOG) --output-directory $(APP)/Contents/Resources
	codesign --force --sign - $(APP)
	$(LSREGISTER) -f $(APP)

# Replaces /Applications/Buchhalter.app. Only on the user's request.
install: app
	rm -rf $(INSTALLED)
	cp -R $(APP) $(INSTALLED)
	$(LSREGISTER) -u $(CURDIR)/$(APP)
	$(LSREGISTER) -f $(INSTALLED)

test:
	swift test

# Finds the texts and syncs them into the catalog. The compiler emits the
# .stringsdata files, so keys with interpolations carry the right
# placeholders (%@, %lld); `xcstringstool extract` on the sources alone
# writes "%arg". New keys arrive as "new" without a German value; the
# catalog test fails until they are translated.
STRINGS_DIR := $(CURDIR)/build/strings
strings:
	rm -rf $(STRINGS_DIR) build/strings-build
	mkdir -p $(STRINGS_DIR)
	swift build --scratch-path build/strings-build \
		-Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc $(STRINGS_DIR)
	$(XCSTRINGSTOOL) sync $(CATALOG) --stringsdata $(STRINGS_DIR)/*.stringsdata

clean:
	rm -rf .build build
