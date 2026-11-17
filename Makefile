APP        := build/Buchhalter.app
BIN        := .build/release/buchhalter
CATALOG    := Resources/Localizable.xcstrings
INFO_CATALOG := Resources/InfoPlist.xcstrings
INSTALLED  := /Applications/Buchhalter.app
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
XCSTRINGSTOOL := xcrun xcstringstool
SOURCES    := $(shell find Sources -name '*.swift') Package.swift

# Signing. The app is sandboxed and signed with the Apple Development
# certificate and a macOS App Development provisioning profile that allows the
# iCloud container, saved outside the repo (it names this Mac).
BUNDLE_ID    := de.juergenalbertsen.buchhalter
CONTAINER_ID := iCloud.$(BUNDLE_ID)
TEAM_ID      := 3PT9KVM9AJ
SIGN_ID      := Apple Development
PROFILE      ?= $(HOME)/Library/Developer/Buchhalter/Buchhalter_Development.provisionprofile
ENTITLEMENTS := Resources/Buchhalter.entitlements
SCHEMA_APP   := build/BuchhalterSchema.app

.DEFAULT_GOAL := build

.PHONY: build app install cli test strings icon isbn-ranges cloudkit-schema ios ios-sim ios-install clean

# Rebuilt only when a source file is newer than the binary.
$(BIN): $(SOURCES)
	swift build -c release

build: $(BIN)

# Builds the signed, sandboxed bundle at $(1) with CloudKit environment $(2):
# the binary, Info.plist, the icon, Google's attribution graphic, the compiled
# catalogs (en.lproj, de.lproj; InfoPlist.xcstrings gives the camera access
# prompt its German text) and the provisioning profile. Texts live in the main
# bundle, so SwiftUI and the core find them. The entitlements come from the
# template with the identifiers filled in.
define bundle
	@test -f "$(PROFILE)" || { echo "missing provisioning profile: $(PROFILE) (see docs/dev/architecture.md, Build and test)"; exit 1; }
	rm -rf $(1)
	mkdir -p $(1)/Contents/MacOS $(1)/Contents/Resources
	cp $(BIN) $(1)/Contents/MacOS/Buchhalter
	cp Resources/Info.plist $(1)/Contents/Info.plist
	cp Resources/AppIcon.icns $(1)/Contents/Resources/AppIcon.icns
	cp Resources/PoweredByGoogle.png $(1)/Contents/Resources/PoweredByGoogle.png
	$(XCSTRINGSTOOL) compile $(CATALOG) --output-directory $(1)/Contents/Resources
	$(XCSTRINGSTOOL) compile $(INFO_CATALOG) --output-directory $(1)/Contents/Resources
	cp "$(PROFILE)" $(1)/Contents/embedded.provisionprofile
	sed -e 's/@TEAM_ID@/$(TEAM_ID)/g' -e 's/@BUNDLE_ID@/$(BUNDLE_ID)/g' \
		-e 's/@CONTAINER_ID@/$(CONTAINER_ID)/g' -e 's/@CLOUDKIT_ENVIRONMENT@/$(2)/g' \
		$(ENTITLEMENTS) > $(1).entitlements
	codesign --force --options runtime --entitlements $(1).entitlements --sign "$(SIGN_ID)" $(1)
endef

# build/Buchhalter.app: CloudKit's production environment, the one the later
# TestFlight and App Store versions use.
app: $(BIN) $(CATALOG) $(INFO_CATALOG) Resources/Info.plist Resources/AppIcon.icns Resources/PoweredByGoogle.png $(ENTITLEMENTS)
	$(call bundle,$(APP),Production)
	$(LSREGISTER) -f $(APP)

# build/BuchhalterSchema.app: the same app in CloudKit's development
# environment. Started once with `-initializeCloudKitSchema YES` it creates the
# record types on a scratch store and quits; then "Deploy Schema Changes" in
# the CloudKit Console makes them production's. Never used on the library.
cloudkit-schema: $(BIN) $(CATALOG) $(INFO_CATALOG) Resources/Info.plist Resources/AppIcon.icns Resources/PoweredByGoogle.png $(ENTITLEMENTS)
	$(call bundle,$(SCHEMA_APP),Development)

# Replaces /Applications/Buchhalter.app. Only on the user's request.
install: app
	rm -rf $(INSTALLED)
	cp -R $(APP) $(INSTALLED)
	$(LSREGISTER) -u $(CURDIR)/$(APP)
	$(LSREGISTER) -f $(INSTALLED)

# The command line tool for maintenance on the library (find-covers), as
# build/buchhalter-cli. `build/buchhalter-cli help` lists the commands.
CLI := build/buchhalter-cli
cli:
	swift build -c release --product buchhalter-cli
	mkdir -p build
	cp .build/release/buchhalter-cli $(CLI)

test:
	swift test

# The iOS app (iPhone and iPad), from iOS/Buchhalter.xcodeproj, which
# compiles the shared App and Views folders and links the package. Automatic
# signing with the team: building for DEVICE (its name in `xcrun devicectl
# list devices`; Developer Mode on) registers it in the development profile
# the first time. build/ios/Buchhalter.app talks to CloudKit Production, like
# the Mac app.
IOS_PROJECT := iOS/Buchhalter.xcodeproj
IOS_DERIVED := build/ios-derived
IOS_APP     := build/ios/Buchhalter.app
XCODEBUILD  := xcodebuild -project $(IOS_PROJECT) -scheme Buchhalter -derivedDataPath $(IOS_DERIVED)
DEVICE      ?= jaPhone

ios:
	$(XCODEBUILD) -configuration Release -destination 'platform=iOS,name=$(DEVICE)' \
		-allowProvisioningUpdates -allowProvisioningDeviceRegistration build
	rm -rf $(IOS_APP)
	mkdir -p build/ios
	cp -R $(IOS_DERIVED)/Build/Products/Release-iphoneos/Buchhalter.app $(IOS_APP)

# A simulator build without signing, for agents: it compiles everything the
# device build does.
ios-sim:
	$(XCODEBUILD) -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

# Installs build/ios/Buchhalter.app on DEVICE. The user runs it:
# `make ios-install`, or `make ios-install DEVICE=<iPad name>`.
ios-install: ios
	xcrun devicectl device install app --device "$(DEVICE)" $(IOS_APP)


# Finds the texts of the Mac and iOS apps and syncs them into the catalog.
# The compiler emits the .stringsdata files, so keys with interpolations
# carry the right placeholders (%@, %lld); `xcstringstool extract` on the
# sources alone writes "%arg". The iOS build passes the same flags instead of
# SWIFT_EMIT_LOC_STRINGS, which would let Xcode rewrite the catalog with the
# iOS texts alone. New keys arrive as "new" without a German value; the
# catalog test fails until they are translated.
STRINGS_DIR := $(CURDIR)/build/strings
strings:
	rm -rf $(STRINGS_DIR) build/strings-build build/strings-ios
	mkdir -p $(STRINGS_DIR)/ios
	swift build --scratch-path build/strings-build \
		-Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc $(STRINGS_DIR)
	xcodebuild -project $(IOS_PROJECT) -scheme Buchhalter -derivedDataPath build/strings-ios \
		-configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO \
		OTHER_SWIFT_FLAGS='$$(inherited) -emit-localized-strings -emit-localized-strings-path $(STRINGS_DIR)/ios' build
	$(XCSTRINGSTOOL) sync $(CATALOG) --stringsdata $(STRINGS_DIR)/*.stringsdata $(STRINGS_DIR)/ios/*.stringsdata

# Downloads the International ISBN Agency's current range message and
# regenerates Sources/BuchhalterCore/Logic/ISBNRanges.swift, which is
# committed, so the build needs no network. Run it when new ranges matter.
isbn-ranges:
	mkdir -p build
	curl -fsS -o build/RangeMessage.xml https://www.isbn-international.org/export_rangemessage.xml
	swift Scripts/make-isbn-ranges.swift build/RangeMessage.xml Sources/BuchhalterCore/Logic/ISBNRanges.swift

# Redraws the app icon (Scripts/make-icon.swift) into Resources/AppIcon.icns,
# which is committed, so `make app` needs no drawing step.
icon:
	rm -rf build/AppIcon.iconset
	mkdir -p build
	swift Scripts/make-icon.swift build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

clean:
	rm -rf .build build
