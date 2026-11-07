SDK ?= iphoneos
IOS_DEPLOYMENT_TARGET ?= 15.0
ARCH ?= arm64
CXX = xcrun --sdk $(SDK) clang++
OUT_DIR := build
TARGET := $(OUT_DIR)/libESPRuntime.dylib
SOURCES := Runtime/Logger.mm Runtime/ScriptValidator.mm Runtime/ScriptManager.mm Runtime/ESPRuntime.mm
SDKROOT := $(shell xcrun --sdk $(SDK) --show-sdk-path)
CXXFLAGS := -std=c++17 -fobjc-arc -fPIC -target $(ARCH)-apple-ios$(IOS_DEPLOYMENT_TARGET) -isysroot $(SDKROOT) -I./Runtime
LDFLAGS := -dynamiclib -install_name @rpath/libESPRuntime.dylib -framework Foundation -framework JavaScriptCore -framework UIKit

.PHONY: all clean

all: $(TARGET)

$(OUT_DIR):
	mkdir -p $(OUT_DIR)

$(TARGET): $(SOURCES) | $(OUT_DIR)
	$(CXX) $(CXXFLAGS) $(SOURCES) -o $@ $(LDFLAGS)

clean:
	rm -rf $(OUT_DIR)
