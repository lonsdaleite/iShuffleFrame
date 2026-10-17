# Legacy build for old devices: armv7 + arm64, iOS 9+, fakesigned, packaged as a .deb for jailbroken devices.
# `make deb ROOTLESS=1` builds an arm64 package for rootless jailbreaks (Dopamine, palera1n): the app goes to /var/jb.
# The regular build (iOS 15+) is the Xcode project generated from project.yml.

NAME       := iShuffleFrame
BUNDLE_ID  := com.lonsdaleite.ishuffleframe
VERSION    := $(shell sed -n 's/^ *MARKETING_VERSION: *//p' project.yml)
BUILD      := $(shell sed -n 's/^ *CURRENT_PROJECT_VERSION: *//p' project.yml)
MIN_IOS    := 9.3
ARCHS      := armv7 arm64
LEGACY_SDK ?= $(HOME)/theos/sdks/iPhoneOS9.3.sdk

ifdef ROOTLESS
PREFIX   := /var/jb
DEB_ARCH := iphoneos-arm64
OUT      := build/rootless
else
PREFIX   :=
DEB_ARCH := iphoneos-arm
OUT      := build/legacy
endif

BIN     := build/legacy/bin
STAGE   := $(OUT)/stage
APP     := $(STAGE)$(PREFIX)/Applications/$(NAME).app
DEB     := $(OUT)/$(BUNDLE_ID)_$(VERSION)-$(BUILD)_$(DEB_ARCH).deb
SCRIPTS := sed -e 's|@PREFIX@|$(PREFIX)|g' -e 's/@VERSION@/$(VERSION)-$(BUILD)/' -e 's/@BUNDLE_ID@/$(BUNDLE_ID)/' \
           -e 's/@DEB_ARCH@/$(DEB_ARCH)/' 
ICON    := Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
SOURCES := $(wildcard Sources/*.m)
HEADERS := $(wildcard Sources/*.h)

CFLAGS := -isysroot $(LEGACY_SDK) -fobjc-arc -fno-objc-exceptions -fno-objc-convert-messages-to-runtime-calls -fobjc-runtime=ios-$(MIN_IOS) -O2 -Wall -Wextra -Wno-unused-parameter \
          -Werror=unguarded-availability -Werror=objc-method-access -ISources
# armv7 is built as ARM code, not Thumb: the current ld drops the Thumb bit from the entry point and method
# addresses, and the CPU would run Thumb code in ARM mode.
FRAMEWORKS := -framework Foundation -framework UIKit -framework CoreGraphics -framework Photos -framework ImageIO -framework QuartzCore

.PHONY: all deb app sdk test clean

all: deb

sdk:
	scripts/fetch-sdk.sh

$(LEGACY_SDK):
	@echo "Missing $(LEGACY_SDK); run 'make sdk'" && exit 1

$(BIN)/$(NAME)-%: $(SOURCES) $(HEADERS) | $(LEGACY_SDK)
	@mkdir -p $(dir $@)
	xcrun clang -target $*-apple-ios$(MIN_IOS) $(CFLAGS) $(if $(filter armv7,$*),-marm) $(EXTRA_CFLAGS) $(SOURCES) $(FRAMEWORKS) -o $@

$(BIN)/$(NAME): $(foreach arch,$(ARCHS),$(BIN)/$(NAME)-$(arch))
	lipo -create $^ -output $@

app: $(BIN)/$(NAME) Resources/Info.plist project.yml packaging/entitlements.plist $(ICON)
	rm -rf $(STAGE) && mkdir -p $(APP)
ifdef ROOTLESS
	lipo $(BIN)/$(NAME) -thin arm64 -output $(APP)/$(NAME)
else
	cp $(BIN)/$(NAME) $(APP)/$(NAME)
endif
	sed -e 's/$$(EXECUTABLE_NAME)/$(NAME)/; s/$$(PRODUCT_NAME)/$(NAME)/' \
	    -e 's/$$(PRODUCT_BUNDLE_IDENTIFIER)/$(BUNDLE_ID)/g' \
	    -e 's/$$(MARKETING_VERSION)/$(VERSION)/; s/$$(CURRENT_PROJECT_VERSION)/$(BUILD)/' \
	    Resources/Info.plist > $(APP)/Info.plist
	plutil -remove UILaunchStoryboardName $(APP)/Info.plist
	plutil -insert MinimumOSVersion -string $(MIN_IOS) $(APP)/Info.plist
	plutil -insert CFBundleSupportedPlatforms -json '["iPhoneOS"]' $(APP)/Info.plist
	plutil -insert UIDeviceFamily -json '[1,2]' $(APP)/Info.plist
	# Icons as plain files: the asset catalog compiler of current Xcode does not target iOS 9.
	for icon in 60x60@2x:120 60x60@3x:180 76x76:76 76x76@2x:152 83.5x83.5@2x:167; do \
	    sips -z $${icon#*:} $${icon#*:} $(ICON) --out $(APP)/AppIcon$${icon%:*}.png >/dev/null || exit 1; \
	done
	plutil -insert CFBundleIcons -json '{"CFBundlePrimaryIcon":{"CFBundleIconFiles":["AppIcon60x60"]}}' $(APP)/Info.plist
	plutil -insert CFBundleIcons~ipad -json '{"CFBundlePrimaryIcon":{"CFBundleIconFiles":["AppIcon60x60","AppIcon76x76","AppIcon83.5x83.5"]}}' $(APP)/Info.plist
	plutil -lint $(APP)/Info.plist
	# Without these an app in /Applications gets a sandbox with no writable home on iOS 12+: settings and the
	# saved cycle would not persist.
	ldid -Spackaging/entitlements.plist $(APP)/$(NAME)

deb: app
	rm -rf $(STAGE)/DEBIAN && mkdir -p $(STAGE)/DEBIAN
	$(SCRIPTS) packaging/control > $(STAGE)/DEBIAN/control
	for f in postinst postrm; do $(SCRIPTS) packaging/$$f > $(STAGE)/DEBIAN/$$f && chmod 755 $(STAGE)/DEBIAN/$$f; done
	dpkg-deb -Zgzip --root-owner-group -b $(STAGE) $(DEB)
	@echo "Built $(DEB)"

test:
	xcodegen generate
	xcodebuild -project $(NAME).xcodeproj -scheme $(NAME) -derivedDataPath build/DerivedData \
	    -destination 'platform=iOS Simulator,name=iPad mini (A17 Pro)' test

clean:
	rm -rf build
