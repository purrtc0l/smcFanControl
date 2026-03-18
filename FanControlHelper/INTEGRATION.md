# OCLP Boot Fan Daemon — Integration Guide

## Overview

This adds a LaunchDaemon that applies saved fan minimum RPM settings at boot,
before the user logs in. This is critical for OCLP (OpenCore Legacy Patcher)
Macs where the SMC fan controller defaults to maximum speed until software
sets the minimum RPM.

## Architecture

```
Boot → launchd loads com.smcfancontrol.bootdaemon.plist
     → runs /Library/Application Support/smcFanControl/smcfancontrold
     → detects OCLP (skips if not OCLP, unless forced)
     → reads /Library/Application Support/smcFanControl/fan-settings.plist
     → writes F{n}Mn keys to SMC
     → logs to /var/log/smcfancontrold.log
     → exits
```

## Files

### New files (daemon):
- `FanControlHelper/smcfancontrold.c` — The daemon binary source
- `FanControlHelper/OCLPDetect.h` — OCLP detection API (C header)
- `FanControlHelper/OCLPDetect.c` — OCLP detection implementation
- `FanControlHelper/com.smcfancontrol.bootdaemon.plist` — LaunchDaemon plist
- `FanControlHelper/fan-settings-example.plist` — Example config
- `FanControlHelper/Makefile` — Standalone build/install

### New files (app integration):
- `Classes/OCLPHelper.h` — Objective-C OCLP helper API
- `Classes/OCLPHelper.m` — OCLP detection, daemon install/uninstall, settings sync

### Modified files:
- `Classes/FanControl.m` — Added OCLPHelper import, first-launch prompt, settings sync

## Xcode Project Integration

### 1. Add a new target for smcfancontrold

1. In Xcode, File → New → Target → macOS → Command Line Tool
2. Name: `smcfancontrold`, Language: C
3. Add these source files to the target:
   - `FanControlHelper/smcfancontrold.c`
   - `FanControlHelper/OCLPDetect.c`
   - `FanControlHelper/OCLPDetect.h`
4. Link frameworks: `IOKit.framework`, `CoreFoundation.framework`
5. Build Settings:
   - `MACOSX_DEPLOYMENT_TARGET` = `10.13`
   - `GCC_PREPROCESSOR_DEFINITIONS` = (none needed, this is standalone)
6. Under the main app target → Build Phases → Copy Bundle Resources:
   - Add the built `smcfancontrold` binary
   - Add `com.smcfancontrol.bootdaemon.plist`
7. Add a "Target Dependency" from the main app to `smcfancontrold`

### 2. Add OCLPHelper to the main app target

1. Add `Classes/OCLPHelper.h` and `Classes/OCLPHelper.m` to the smcFanControl target
2. The `#import "OCLPHelper.h"` is already added to `FanControl.m`

### 3. Build and test

```bash
# Build daemon standalone
cd FanControlHelper
make

# Test OCLP detection (dry run)
sudo ./smcfancontrold -n

# Test with force flag (non-OCLP Mac)
sudo ./smcfancontrold -f -c fan-settings-example.plist

# Full install
sudo make install
```

## How Settings Flow

1. User adjusts fan slider in smcFanControl.app
2. `fanSliderChanged:` writes to SMC and saves to NSUserDefaults
3. `[OCLPHelper syncFanSettingsWithDaemon]` writes to system-level plist
4. On next boot, `smcfancontrold` reads that plist and applies via SMC

## OCLP Detection Methods

The daemon checks four indicators (any one is sufficient):

| Method | Check | Reliability |
|--------|-------|-------------|
| Directory | `/Library/OpenCore` exists | High — OCLP always creates this |
| NVRAM | `opencore-version` key present | High — set by OpenCore bootloader |
| Directory | `/Library/Application Support/Dortania` | Medium — OCLP support files |
| Boot args | `amfi_get_out_of_my_way`, `revpatch=`, etc. | Medium — common OCLP flags |

## Daemon CLI Options

```
Usage: smcfancontrold [options]
  -c <path>   Config plist path (default: /Library/Application Support/smcFanControl/fan-settings.plist)
  -f          Force apply even if OCLP is not detected
  -n          Dry run (detect OCLP and read config, but don't write SMC)
  -q          Quiet mode (no log file, stderr only)
  -h          Show help
```

## Security Notes

- The daemon runs as root (required for SMC writes)
- The LaunchDaemon plist must be owned by root:wheel with 644 permissions
- The daemon binary must be owned by root:wheel with 755 permissions
- Installation requires admin authentication (shown via standard macOS dialog)
- The fan-settings.plist is readable by all but only writable with admin privileges
