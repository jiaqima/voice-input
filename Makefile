APP_NAME = VoiceInput
BUILD_DIR = .build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
BINARY = $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
INSTALL_DIR = ~/Applications

SWIFT_FILES = $(shell find Sources -name '*.swift')
FRAMEWORKS = -framework AppKit -framework AVFoundation -framework Speech -framework Carbon -framework CoreGraphics -framework QuartzCore

# Use Xcode toolchain if available, fall back to CLI tools
XCODE_TC = /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain
SWIFTC = $(shell [ -x "$(XCODE_TC)/usr/bin/swiftc" ] && echo "$(XCODE_TC)/usr/bin/swiftc" || echo "swiftc")
SDK = $(shell DEVELOPER_DIR=$$([ -d /Applications/Xcode.app ] && echo /Applications/Xcode.app/Contents/Developer || echo /Library/Developer/CommandLineTools) xcrun --sdk macosx --show-sdk-path 2>/dev/null)
SWIFT_FLAGS = -target arm64-apple-macosx14.0 -swift-version 5 -sdk $(SDK)

.PHONY: build run install clean

build: $(BINARY)

$(BINARY): $(SWIFT_FILES) Info.plist VoiceInput.entitlements
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	$(SWIFTC) $(SWIFT_FLAGS) $(FRAMEWORKS) $(SWIFT_FILES) -o "$(BINARY)"
	@cp Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	@codesign --force --sign - --entitlements VoiceInput.entitlements "$(APP_BUNDLE)"
	@echo "Built: $(APP_BUNDLE)"

run: build
	@open "$(APP_BUNDLE)"

install: build
	@mkdir -p "$(INSTALL_DIR)"
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@cp -R "$(APP_BUNDLE)" "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME).app"

clean:
	@rm -rf "$(BUILD_DIR)"
