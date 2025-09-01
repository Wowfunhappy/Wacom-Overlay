CC = gcc
CFLAGS = -Wall -g -arch x86_64
LDFLAGS = -framework Cocoa

PRODUCT_NAME = Wacom Overlay
EXECUTABLE_NAME = WacomOverlay
MACOSX_DEPLOYMENT_TARGET = 10.9

SOURCES = main.m AppDelegate.m TabletApplication.m TabletEvents.m OverlayWindow.m DrawView.m ControlPanel.m
OBJECTS = $(SOURCES:.m=.o)
APP_DIR = $(PRODUCT_NAME).app
CONTENTS_DIR = $(APP_DIR)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
RESOURCES_DIR = $(CONTENTS_DIR)/Resources

all: app

app: $(APP_DIR)

$(APP_DIR): $(EXECUTABLE_NAME)
	mkdir -p "$(MACOS_DIR)"
	mkdir -p "$(RESOURCES_DIR)"
	cp $(EXECUTABLE_NAME) "$(MACOS_DIR)/"
	cp Info.plist "$(CONTENTS_DIR)/Info.plist"
	sed -i '' 's/<string>[0-9][0-9][0-9][0-9]\.[0-9][0-9]\.[0-9][0-9]<\/string>/<string>'$$(date +%Y.%m.%d)'<\/string>/' "$(CONTENTS_DIR)/Info.plist"
	cp AppIcon.icns "$(RESOURCES_DIR)/"
	cp menuIcon.png "$(RESOURCES_DIR)/"
	cp menuIcon@2x.png "$(RESOURCES_DIR)/"
	cp KeyboardShortcuts.txt "$(RESOURCES_DIR)/"
	codesign --force --sign "Wowfunhappy" "$(APP_DIR)"

$(EXECUTABLE_NAME): $(OBJECTS)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^

%.o: %.m
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJECTS) $(EXECUTABLE_NAME)
	rm -rf "$(APP_DIR)"

.PHONY: all app clean