APP_NAME = VoiceInput
BUILD_DIR = .build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
BINARY = $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
INSTALL_DIR = $(HOME)/Applications
CONFIG_DIR = $(HOME)/.config/voice-input
CONFIG_FILE = $(CONFIG_DIR)/config.json

SWIFT_FILES = $(shell find Sources -name '*.swift')
FRAMEWORKS = -framework AppKit -framework AVFoundation -framework Speech -framework Carbon -framework CoreGraphics -framework QuartzCore -framework Accelerate -framework Metal

# Use Xcode toolchain if available, fall back to CLI tools
XCODE_TC = /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain
SWIFTC = $(shell [ -x "$(XCODE_TC)/usr/bin/swiftc" ] && echo "$(XCODE_TC)/usr/bin/swiftc" || echo "swiftc")
SDK = $(shell DEVELOPER_DIR=$$([ -d /Applications/Xcode.app ] && echo /Applications/Xcode.app/Contents/Developer || echo /Library/Developer/CommandLineTools) xcrun --sdk macosx --show-sdk-path 2>/dev/null)
SWIFT_FLAGS = -target arm64-apple-macosx14.0 -swift-version 5 -sdk $(SDK)

# Code signing identity. Use "make SIGN_IDENTITY=VoiceInput\ Dev install" with a
# self-signed certificate to preserve TCC permissions across rebuilds.
# Default: ad-hoc signing (permissions reset on every rebuild).
SIGN_IDENTITY ?= -

# whisper.cpp
WHISPER_DIR = vendor/whisper.cpp
WHISPER_BUILD = $(WHISPER_DIR)/build
WHISPER_LIB = $(WHISPER_BUILD)/src/libwhisper.a
BRIDGING_HEADER = Sources/Bridge/whisper-bridging-header.h
MODEL_DIR = models
DEFAULT_MODEL ?= large-v3-turbo-q8_0
INSTALLED_MODEL_PATH = $(INSTALL_DIR)/$(APP_NAME).app/Contents/Resources/ggml-$(DEFAULT_MODEL).bin

.PHONY: build run install clean whisper-lib download-model install-config-default

build: $(BINARY)

$(BINARY): $(SWIFT_FILES) $(WHISPER_LIB) Info.plist VoiceInput.entitlements
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	$(SWIFTC) $(SWIFT_FLAGS) $(FRAMEWORKS) \
		-import-objc-header $(BRIDGING_HEADER) \
		-Xcc -I$(WHISPER_DIR)/include -Xcc -I$(WHISPER_DIR)/ggml/include \
		-Xlinker -L$(WHISPER_BUILD)/src \
		-Xlinker -L$(WHISPER_BUILD)/ggml/src \
		-Xlinker -L$(WHISPER_BUILD)/ggml/src/ggml-metal \
		-Xlinker -L$(WHISPER_BUILD)/ggml/src/ggml-blas \
		-Xlinker -lwhisper -Xlinker -lggml -Xlinker -lggml-base \
		-Xlinker -lggml-cpu -Xlinker -lggml-metal -Xlinker -lggml-blas \
		-lc++ \
		$(SWIFT_FILES) -o "$(BINARY)"
	@cp Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	@if [ -f "$(MODEL_DIR)/ggml-$(DEFAULT_MODEL).bin" ]; then \
		cp "$(MODEL_DIR)/ggml-$(DEFAULT_MODEL).bin" "$(APP_BUNDLE)/Contents/Resources/"; \
	fi
	@codesign --force --sign "$(SIGN_IDENTITY)" --entitlements VoiceInput.entitlements "$(APP_BUNDLE)"
	@echo "Built: $(APP_BUNDLE)"

# Build whisper.cpp as a static library
whisper-lib: $(WHISPER_LIB)

$(WHISPER_LIB):
	cd $(WHISPER_DIR) && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
	cmake -B build \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DCMAKE_OSX_SYSROOT=$$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun --sdk macosx --show-sdk-path) \
		-DCMAKE_C_COMPILER=$$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun --find cc) \
		-DCMAKE_CXX_COMPILER=$$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun --find c++) \
		-DBUILD_SHARED_LIBS=OFF \
		-DWHISPER_BUILD_EXAMPLES=OFF \
		-DWHISPER_BUILD_TESTS=OFF \
		-DCMAKE_BUILD_TYPE=Release
	cd $(WHISPER_DIR) && cmake --build build --config Release -j$$(sysctl -n hw.ncpu)

# Download a whisper model (default: large-v3-turbo-q8_0)
download-model:
	@mkdir -p $(MODEL_DIR)
	@echo "Downloading ggml-$(DEFAULT_MODEL).bin..."
	@curl -L --progress-bar -o "$(MODEL_DIR)/ggml-$(DEFAULT_MODEL).bin" \
		"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$(DEFAULT_MODEL).bin"
	@echo "Downloaded: $(MODEL_DIR)/ggml-$(DEFAULT_MODEL).bin"

run: build
	@open "$(APP_BUNDLE)"

install: build
	@mkdir -p "$(INSTALL_DIR)"
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	@cp -R "$(APP_BUNDLE)" "$(INSTALL_DIR)/$(APP_NAME).app"
	@$(MAKE) install-config-default HOME="$(HOME)" INSTALL_DIR="$(INSTALL_DIR)" APP_NAME="$(APP_NAME)" DEFAULT_MODEL="$(DEFAULT_MODEL)"
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME).app"

install-config-default:
	@if [ -f "$(CONFIG_FILE)" ]; then \
		echo "Config exists; leaving it unchanged: $(CONFIG_FILE)"; \
	elif [ ! -f "$(INSTALLED_MODEL_PATH)" ]; then \
		echo "Default model not found in installed app; skipping config creation: $(INSTALLED_MODEL_PATH)"; \
	else \
		mkdir -p "$(CONFIG_DIR)"; \
		printf '%s\n' \
			'{' \
			'  "language": "en-US",' \
			'  "sttBackend": "apple",' \
			'  "whisperModelPath": "$(INSTALLED_MODEL_PATH)",' \
			'  "llmEnabled": false,' \
			'  "llmBaseURL": "",' \
			'  "llmAPIKey": "",' \
			'  "llmModel": ""' \
			'}' > "$(CONFIG_FILE)"; \
		echo "Created default config: $(CONFIG_FILE)"; \
	fi

clean:
	@rm -rf "$(BUILD_DIR)"
	@rm -rf "$(WHISPER_BUILD)"
