TARGET     = arm64-apple-ios15.0
SDK        = $(shell xcrun --sdk iphoneos --show-sdk-path)
CC         = $(shell xcrun --sdk iphoneos --find clang++)
ARCH       = -arch arm64
CFLAGS     = $(ARCH) -isysroot $(SDK) -std=c++17 -fobjc-arc \
             -fvisibility=hidden -O2 -mios-version-min=15.0
LDFLAGS    = $(ARCH) -isysroot $(SDK) -dynamiclib \
             -framework Foundation -framework UIKit \
             -framework QuartzCore -framework CoreGraphics \
             -lobjc -lc++ -mios-version-min=15.0

SRCS = src/main.mm \
       src/bypass/Bypass.mm \
       src/bypass/AntiDebug.mm \
       src/features/Aimbot.mm \
       src/features/ESP.mm \
       src/ui/Menu.mm \
       fishhook/fishhook.c

OUT = FFNET.dylib

all:
	$(CC) $(CFLAGS) $(LDFLAGS) $(SRCS) -o $(OUT)
	@echo "[FFNET] Build done → $(OUT)"

clean:
	rm -f $(OUT)
