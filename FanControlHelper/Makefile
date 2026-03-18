# smcfancontrold — Boot-time fan control daemon for OCLP Macs
#
# Build:   make
# Install: sudo make install
# Remove:  sudo make uninstall
#
# Requires: macOS SDK with IOKit and CoreFoundation

CC = clang
CFLAGS = -Wall -Wextra -O2 -mmacosx-version-min=10.13
LDFLAGS = -framework IOKit -framework CoreFoundation

SOURCES = smcfancontrold.c OCLPDetect.c
TARGET = smcfancontrold

INSTALL_DIR = /Library/Application Support/smcFanControl
LAUNCHDAEMONS_DIR = /Library/LaunchDaemons
PLIST = com.smcfancontrol.bootdaemon.plist

.PHONY: all clean install uninstall

all: $(TARGET)

$(TARGET): $(SOURCES)
	$(CC) $(CFLAGS) -o $@ $(SOURCES) $(LDFLAGS)

clean:
	rm -f $(TARGET)

install: $(TARGET)
	@echo "Installing smcfancontrold..."
	mkdir -p "$(INSTALL_DIR)"
	cp $(TARGET) "$(INSTALL_DIR)/$(TARGET)"
	chmod 755 "$(INSTALL_DIR)/$(TARGET)"
	chown root:wheel "$(INSTALL_DIR)/$(TARGET)"
	cp $(PLIST) "$(LAUNCHDAEMONS_DIR)/$(PLIST)"
	chmod 644 "$(LAUNCHDAEMONS_DIR)/$(PLIST)"
	chown root:wheel "$(LAUNCHDAEMONS_DIR)/$(PLIST)"
	@echo "Loading daemon..."
	launchctl load "$(LAUNCHDAEMONS_DIR)/$(PLIST)" 2>/dev/null || true
	@echo "Done. The daemon will run at next boot."
	@echo "To test now: sudo '$(INSTALL_DIR)/$(TARGET)' -f"

uninstall:
	@echo "Uninstalling smcfancontrold..."
	launchctl unload "$(LAUNCHDAEMONS_DIR)/$(PLIST)" 2>/dev/null || true
	rm -f "$(LAUNCHDAEMONS_DIR)/$(PLIST)"
	rm -f "$(INSTALL_DIR)/$(TARGET)"
	@echo "Done. Fan settings plist left in place at $(INSTALL_DIR)/fan-settings.plist"
