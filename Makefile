# Legacy build for old devices: armv7 + arm64, iOS 9+, fakesigned, packaged as a .deb for jailbroken devices.
# The regular build (iOS 15+) is the Xcode project generated from project.yml.

NAME       := iShuffleFrame
BUNDLE_ID  := com.lonsdaleite.ishuffleframe
VERSION    := $(shell sed -n 's/^ *MARKETING_VERSION: *//p' project.yml)
BUILD      := $(shell sed -n 's/^ *CURRENT_PROJECT_VERSION: *//p' project.yml)
MIN_IOS    := 9.3
ARCHS      := armv7 arm64
LEGACY_SDK ?= $(HOME)/theos/sdks/iPhoneOS9.3.sdk

OUT     := build/legacy
APP     := $(OUT)/stage/Applications/$(NAME).app
DEB     := $(OUT)/$(BUNDLE_ID)_$(VERSION)-$(BUILD)_iphoneos-arm.deb
SOURCES := $(wildcard Sources/*.m)
HEADERS := $(wildcard Sources/*.h)

CFLAGS := -isysroot $(LEGACY_SDK) -fobjc-arc -fno-objc-exceptions -fno-objc-convert-messages-to-runtime-calls -fobjc-runtime=ios-$(MIN_IOS) -O2 -Wall -Wextra -Wno-unused-parameter \
          -Werror=unguarded-availability -Werror=objc-method-access -ISources
FRAMEWORKS := -framework Foundation -framework UIKit -framework CoreGraphics -framework Photos

.PHONY: all deb app sdk test clean

all: deb

sdk:
	scripts/fetch-sdk.sh

$(LEGACY_SDK):
	@echo "Missing $(LEGACY_SDK); run 'make sdk'" && exit 1

$(OUT)/bin/$(NAME)-%: $(SOURCES) $(HEADERS) | $(LEGACY_SDK)
	@mkdir -p $(dir $@)
	xcrun clang -target $*-apple-ios$(MIN_IOS) $(CFLAGS) $(SOURCES) $(FRAMEWORKS) -o $@

$(OUT)/bin/$(NAME): $(foreach arch,$(ARCHS),$(OUT)/bin/$(NAME)-$(arch))
	lipo -create $^ -output $@

app: $(OUT)/bin/$(NAME) Resources/Info.plist project.yml
	rm -rf $(APP) && mkdir -p $(APP)
	cp $(OUT)/bin/$(NAME) $(APP)/$(NAME)
	sed -e 's/$$(EXECUTABLE_NAME)/$(NAME)/; s/$$(PRODUCT_NAME)/$(NAME)/' \
	    -e 's/$$(PRODUCT_BUNDLE_IDENTIFIER)/$(BUNDLE_ID)/g' \
	    -e 's/$$(MARKETING_VERSION)/$(VERSION)/; s/$$(CURRENT_PROJECT_VERSION)/$(BUILD)/' \
	    Resources/Info.plist > $(APP)/Info.plist
	plutil -remove UILaunchStoryboardName $(APP)/Info.plist
	plutil -insert MinimumOSVersion -string $(MIN_IOS) $(APP)/Info.plist
	plutil -insert CFBundleSupportedPlatforms -json '["iPhoneOS"]' $(APP)/Info.plist
	plutil -insert UIDeviceFamily -json '[1,2]' $(APP)/Info.plist
	plutil -lint $(APP)/Info.plist
	ldid -S $(APP)/$(NAME)

deb: app
	rm -rf $(OUT)/stage/DEBIAN && mkdir -p $(OUT)/stage/DEBIAN
	sed -e 's/@VERSION@/$(VERSION)-$(BUILD)/' -e 's/@BUNDLE_ID@/$(BUNDLE_ID)/' packaging/control > $(OUT)/stage/DEBIAN/control
	install -m 755 packaging/postinst packaging/postrm $(OUT)/stage/DEBIAN/
	dpkg-deb -Zgzip --root-owner-group -b $(OUT)/stage $(DEB)
	@echo "Built $(DEB)"

test:
	xcodegen generate
	xcodebuild -project $(NAME).xcodeproj -scheme $(NAME) -derivedDataPath build/DerivedData \
	    -destination 'platform=iOS Simulator,name=iPad mini (A17 Pro)' test

clean:
	rm -rf build
