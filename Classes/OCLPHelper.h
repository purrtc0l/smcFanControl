/*
 * smcFanControl Community Edition - OCLP Helper
 *
 * Provides OCLP detection and boot daemon management for the main app.
 *
 * Copyright (c) 2024 wolffcatskyy
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 */

#import <Foundation/Foundation.h>

/// Manages OCLP detection and boot daemon installation for smcFanControl.
@interface OCLPHelper : NSObject

/// Returns YES if this Mac is running OpenCore Legacy Patcher.
+ (BOOL)isOCLPMac;

/// Returns a human-readable description of how OCLP was detected.
+ (NSString *)oclpDetectionDescription;

/// Returns YES if the boot daemon is currently installed.
+ (BOOL)isDaemonInstalled;

/// Install the boot daemon (requires admin privileges).
/// Shows an authorization dialog if needed.
/// Returns YES on success.
+ (BOOL)installDaemon;

/// Uninstall the boot daemon (requires admin privileges).
/// Returns YES on success.
+ (BOOL)uninstallDaemon;

/// Write current fan settings to the system-level plist that the boot
/// daemon reads. Called whenever the user changes fan settings in the app.
/// Returns YES on success.
+ (BOOL)syncFanSettingsWithDaemon;

/// Check OCLP status on first launch and prompt user to install daemon.
/// Call this from applicationDidFinishLaunching or awakeFromNib.
+ (void)checkAndPromptForDaemonInstall;

@end
