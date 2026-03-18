/*
 * smcFanControl Community Edition - OCLP Helper
 *
 * Provides OCLP detection and boot daemon management for the main app.
 * This bridges the C-level OCLP detection to the Objective-C app and
 * handles privileged installation of the LaunchDaemon.
 *
 * Copyright (c) 2024 wolffcatskyy
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 */

#import "OCLPHelper.h"
#import "smcWrapper.h"
#import "Constants.h"
#import <Security/Authorization.h>
#import <Security/AuthorizationTags.h>

/* Paths */
static NSString * const kDaemonBinaryInstallPath = @"/Library/Application Support/smcFanControl/smcfancontrold";
static NSString * const kDaemonPlistInstallPath  = @"/Library/LaunchDaemons/com.smcfancontrol.bootdaemon.plist";
static NSString * const kFanSettingsPlistPath     = @"/Library/Application Support/smcFanControl/fan-settings.plist";
static NSString * const kSupportDirPath           = @"/Library/Application Support/smcFanControl";

/* NSUserDefaults keys for tracking OCLP prompts */
static NSString * const kOCLPPromptShown  = @"OCLPDaemonPromptShown";
static NSString * const kOCLPDaemonEnabled = @"OCLPDaemonEnabled";

@implementation OCLPHelper

#pragma mark - OCLP Detection

+ (BOOL)isOCLPMac {
    // Check multiple OCLP indicators
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir;

    // Method 1: /Library/OpenCore directory
    if ([fm fileExistsAtPath:@"/Library/OpenCore" isDirectory:&isDir] && isDir) {
        return YES;
    }

    // Method 2: NVRAM opencore-version key
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/sbin/nvram"];
    [task setArguments:@[@"4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version"]];
    [task setStandardOutput:[NSPipe pipe]];
    [task setStandardError:[NSPipe pipe]];
    @try {
        [task launch];
        [task waitUntilExit];
        if ([task terminationStatus] == 0) return YES;
    } @catch (NSException *e) {
        // nvram not available, skip
    }

    // Method 3: Dortania support directory
    if ([fm fileExistsAtPath:@"/Library/Application Support/Dortania" isDirectory:&isDir] && isDir) {
        return YES;
    }

    // Method 4: boot-args containing OpenCore signatures
    NSTask *bootTask = [[NSTask alloc] init];
    [bootTask setLaunchPath:@"/usr/sbin/nvram"];
    [bootTask setArguments:@[@"boot-args"]];
    NSPipe *pipe = [NSPipe pipe];
    [bootTask setStandardOutput:pipe];
    [bootTask setStandardError:[NSPipe pipe]];
    @try {
        [bootTask launch];
        [bootTask waitUntilExit];
        if ([bootTask terminationStatus] == 0) {
            NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
            NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if ([output containsString:@"amfi_get_out_of_my_way"] ||
                [output containsString:@"ipc_control_port_options"] ||
                [output containsString:@"-lilubetaall"] ||
                [output containsString:@"revpatch="] ||
                [output containsString:@"revblock="]) {
                return YES;
            }
        }
    } @catch (NSException *e) {
        // Skip
    }

    return NO;
}

+ (NSString *)oclpDetectionDescription {
    NSMutableArray *methods = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir;

    if ([fm fileExistsAtPath:@"/Library/OpenCore" isDirectory:&isDir] && isDir)
        [methods addObject:@"/Library/OpenCore"];

    if ([fm fileExistsAtPath:@"/Library/Application Support/Dortania" isDirectory:&isDir] && isDir)
        [methods addObject:@"Dortania directory"];

    // NVRAM check
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/sbin/nvram"];
    [task setArguments:@[@"4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version"]];
    [task setStandardOutput:[NSPipe pipe]];
    [task setStandardError:[NSPipe pipe]];
    @try {
        [task launch];
        [task waitUntilExit];
        if ([task terminationStatus] == 0)
            [methods addObject:@"NVRAM opencore-version"];
    } @catch (NSException *e) {}

    if ([methods count] == 0) {
        return @"No OCLP detected";
    }
    return [NSString stringWithFormat:@"OCLP detected via: %@", [methods componentsJoinedByString:@", "]];
}

#pragma mark - Daemon Management

+ (BOOL)isDaemonInstalled {
    NSFileManager *fm = [NSFileManager defaultManager];
    return [fm fileExistsAtPath:kDaemonBinaryInstallPath] &&
           [fm fileExistsAtPath:kDaemonPlistInstallPath];
}

+ (BOOL)installDaemon {
    // The daemon binary is bundled in the app's Resources
    NSString *bundledBinary = [[NSBundle mainBundle] pathForResource:@"smcfancontrold" ofType:@""];
    NSString *bundledPlist = [[NSBundle mainBundle] pathForResource:@"com.smcfancontrol.bootdaemon" ofType:@"plist"];

    if (!bundledBinary || !bundledPlist) {
        NSLog(@"OCLPHelper: daemon binary or plist not found in bundle");
        return NO;
    }

    // Create a shell script that performs the privileged installation
    NSString *script = [NSString stringWithFormat:
        @"mkdir -p '%@' && "
         "cp '%@' '%@' && "
         "chmod 755 '%@' && "
         "chown root:wheel '%@' && "
         "cp '%@' '%@' && "
         "chmod 644 '%@' && "
         "chown root:wheel '%@' && "
         "launchctl load '%@' 2>/dev/null; true",
        kSupportDirPath,
        bundledBinary, kDaemonBinaryInstallPath,
        kDaemonBinaryInstallPath,
        kDaemonBinaryInstallPath,
        bundledPlist, kDaemonPlistInstallPath,
        kDaemonPlistInstallPath,
        kDaemonPlistInstallPath,
        kDaemonPlistInstallPath
    ];

    BOOL success = [self runPrivilegedScript:script];
    if (success) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kOCLPDaemonEnabled];
        // Sync current fan settings so the daemon has something to apply
        [self syncFanSettingsWithDaemon];
        NSLog(@"OCLPHelper: daemon installed successfully");
    }
    return success;
}

+ (BOOL)uninstallDaemon {
    NSString *script = [NSString stringWithFormat:
        @"launchctl unload '%@' 2>/dev/null; "
         "rm -f '%@' '%@'",
        kDaemonPlistInstallPath,
        kDaemonPlistInstallPath,
        kDaemonBinaryInstallPath
    ];

    BOOL success = [self runPrivilegedScript:script];
    if (success) {
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kOCLPDaemonEnabled];
        NSLog(@"OCLPHelper: daemon uninstalled successfully");
    }
    return success;
}

#pragma mark - Fan Settings Sync

+ (BOOL)syncFanSettingsWithDaemon {
    if (![self isDaemonInstalled]) return NO;

    // Build the fan settings plist from current NSUserDefaults
    int numFans = [smcWrapper get_fan_num];
    NSMutableArray *fansArray = [NSMutableArray array];

    for (int i = 0; i < numFans; i++) {
        NSString *prefKey = [NSString stringWithFormat:@"fan_%d_min_rpm", i];
        int savedRPM = (int)[[NSUserDefaults standardUserDefaults] integerForKey:prefKey];

        // Validate against hardware limits
        int hwMin = [smcWrapper get_min_speed:i];
        int hwMax = [smcWrapper get_max_speed:i];
        if (hwMin <= 0) hwMin = 800;
        if (hwMax <= hwMin) hwMax = hwMin + 4000;
        if (savedRPM < hwMin || savedRPM > hwMax) savedRPM = hwMin;

        [fansArray addObject:@{
            @"id": @(i),
            @"min_rpm": @(savedRPM)
        }];
    }

    NSDictionary *plistDict = @{ @"fans": fansArray };

    // Write to a temp file first, then move with privileges
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"smcfc-fan-settings.plist"];
    BOOL wrote = [plistDict writeToFile:tmpPath atomically:YES];
    if (!wrote) {
        NSLog(@"OCLPHelper: failed to write temp fan-settings plist");
        return NO;
    }

    // Copy with admin privileges to the system location
    NSString *script = [NSString stringWithFormat:
        @"mkdir -p '%@' && cp '%@' '%@' && chmod 644 '%@'",
        kSupportDirPath, tmpPath, kFanSettingsPlistPath, kFanSettingsPlistPath
    ];

    BOOL success = [self runPrivilegedScript:script];
    [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];

    if (success) {
        NSLog(@"OCLPHelper: fan settings synced to %@", kFanSettingsPlistPath);
    }
    return success;
}

#pragma mark - First-Launch Prompt

+ (void)checkAndPromptForDaemonInstall {
    // Only prompt once
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kOCLPPromptShown]) return;

    // Only prompt on OCLP Macs
    if (![self isOCLPMac]) return;

    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kOCLPPromptShown];

    // Delay slightly so the app finishes launching first
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"OCLP Mac Detected"];
        [alert setInformativeText:
            @"Your Mac is running OpenCore Legacy Patcher. On OCLP Macs, "
             "fans run at full speed until smcFanControl starts.\n\n"
             "Would you like to enable boot-time fan control? This installs "
             "a small system daemon that applies your fan settings immediately "
             "at boot, before you even log in.\n\n"
             "You can change this later in Preferences."];
        [alert setAlertStyle:NSAlertStyleInformational];
        [alert addButtonWithTitle:@"Enable Boot Fan Control"];
        [alert addButtonWithTitle:@"Not Now"];

        if (@available(macOS 11.0, *)) {
            // Use SF Symbol for the icon if available
            NSImage *icon = [NSImage imageWithSystemSymbolName:@"fan.floor"
                                     accessibilityDescription:@"Fan"];
            if (icon) [alert setIcon:icon];
        }

        NSModalResponse response = [alert runModal];
        if (response == NSAlertFirstButtonReturn) {
            BOOL installed = [OCLPHelper installDaemon];
            if (installed) {
                NSAlert *successAlert = [[NSAlert alloc] init];
                [successAlert setMessageText:@"Boot Fan Control Enabled"];
                [successAlert setInformativeText:
                    @"The fan control daemon has been installed. Your fan "
                     "settings will now be applied at boot before login.\n\n"
                     "The daemon reads from:\n"
                     "/Library/Application Support/smcFanControl/fan-settings.plist\n\n"
                     "Settings are synced automatically when you adjust fan speeds."];
                [successAlert setAlertStyle:NSAlertStyleInformational];
                [successAlert addButtonWithTitle:@"OK"];
                [successAlert runModal];
            } else {
                NSAlert *errorAlert = [[NSAlert alloc] init];
                [errorAlert setMessageText:@"Installation Failed"];
                [errorAlert setInformativeText:
                    @"Could not install the boot fan control daemon. "
                     "You may need to grant administrator access. "
                     "You can try again from Preferences."];
                [errorAlert setAlertStyle:NSAlertStyleWarning];
                [errorAlert addButtonWithTitle:@"OK"];
                [errorAlert runModal];
            }
        }
    });
}

#pragma mark - Privileged Execution

+ (BOOL)runPrivilegedScript:(NSString *)script {
    // Use AuthorizationCreate + /bin/sh to run privileged commands.
    // This shows the standard macOS admin password dialog.
    AuthorizationRef authRef = NULL;
    OSStatus status = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment,
                                          kAuthorizationFlagDefaults, &authRef);
    if (status != errAuthorizationSuccess) {
        NSLog(@"OCLPHelper: AuthorizationCreate failed: %d", (int)status);
        return NO;
    }

    AuthorizationItem authItem = {
        .name = kAuthorizationRightExecute,
        .valueLength = 0,
        .value = NULL,
        .flags = 0
    };
    AuthorizationRights authRights = {
        .count = 1,
        .items = &authItem
    };

    status = AuthorizationCopyRights(authRef, &authRights, kAuthorizationEmptyEnvironment,
                                     kAuthorizationFlagDefaults |
                                     kAuthorizationFlagInteractionAllowed |
                                     kAuthorizationFlagPreAuthorize |
                                     kAuthorizationFlagExtendRights,
                                     NULL);
    if (status != errAuthorizationSuccess) {
        NSLog(@"OCLPHelper: AuthorizationCopyRights failed: %d", (int)status);
        AuthorizationFree(authRef, kAuthorizationFlagDefaults);
        return NO;
    }

    // Write the script to a temp file and execute it with /bin/sh via STPrivilegedTask pattern
    NSString *tmpScript = [NSTemporaryDirectory() stringByAppendingPathComponent:@"smcfc-install.sh"];
    NSError *writeError = nil;
    [script writeToFile:tmpScript atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
    if (writeError) {
        NSLog(@"OCLPHelper: failed to write install script: %@", writeError);
        AuthorizationFree(authRef, kAuthorizationFlagDefaults);
        return NO;
    }

    // Use NSTask with the authorization to run as root
    // Since AuthorizationExecuteWithPrivileges is deprecated, we use a helper approach:
    // Write the script and use osascript "do shell script ... with administrator privileges"
    AuthorizationFree(authRef, kAuthorizationFlagDefaults);

    // Use osascript for privilege escalation (modern macOS compatible approach)
    NSString *escapedScript = [script stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    NSString *osaScript = [NSString stringWithFormat:
        @"do shell script '%@' with administrator privileges", escapedScript];

    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/osascript"];
    [task setArguments:@[@"-e", osaScript]];
    [task setStandardOutput:[NSPipe pipe]];
    [task setStandardError:[NSPipe pipe]];

    @try {
        [task launch];
        [task waitUntilExit];
        [[NSFileManager defaultManager] removeItemAtPath:tmpScript error:nil];
        return ([task terminationStatus] == 0);
    } @catch (NSException *e) {
        NSLog(@"OCLPHelper: privileged execution failed: %@", e);
        [[NSFileManager defaultManager] removeItemAtPath:tmpScript error:nil];
        return NO;
    }
}

@end
