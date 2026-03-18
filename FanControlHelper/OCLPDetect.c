/*
 * smcFanControl Community Edition - OCLP Detection
 * Detects if the Mac is running OpenCore Legacy Patcher.
 *
 * Copyright (c) 2024 wolffcatskyy
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 */

#include "OCLPDetect.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

/* Check if a directory exists */
static bool dir_exists(const char *path)
{
    struct stat sb;
    return (stat(path, &sb) == 0 && S_ISDIR(sb.st_mode));
}

/* Check NVRAM for OpenCore version key */
static bool nvram_has_opencore(void)
{
    /*
     * OCLP sets the NVRAM variable:
     *   4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version
     *
     * We shell out to nvram(8) since IOKit NVRAM access from a
     * non-privileged context can be tricky. The daemon runs as root
     * so this is fine.
     */
    int ret = system("nvram 4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version >/dev/null 2>&1");
    return (ret == 0);
}

/* Check boot-args for OpenCore signatures */
static bool bootargs_has_opencore(void)
{
    FILE *fp = popen("nvram boot-args 2>/dev/null", "r");
    if (!fp) return false;

    char buf[1024];
    bool found = false;
    while (fgets(buf, sizeof(buf), fp)) {
        /* Common OCLP boot-args patterns */
        if (strstr(buf, "amfi_get_out_of_my_way") ||
            strstr(buf, "ipc_control_port_options") ||
            strstr(buf, "-lilubetaall") ||
            strstr(buf, "revpatch=") ||
            strstr(buf, "revblock=")) {
            found = true;
            break;
        }
    }
    pclose(fp);
    return found;
}

int oclp_detect(void)
{
    int flags = 0;

    /* Method 1: Check for /Library/OpenCore (OCLP installs its files here) */
    if (dir_exists("/Library/OpenCore")) {
        flags |= OCLP_METHOD_OPENCORE_DIR;
    }

    /* Method 2: Check NVRAM for opencore-version key */
    if (nvram_has_opencore()) {
        flags |= OCLP_METHOD_NVRAM;
    }

    /* Method 3: Check for Dortania support directory */
    if (dir_exists("/Library/Application Support/Dortania")) {
        flags |= OCLP_METHOD_DORTANIA_DIR;
    }

    /* Method 4: Check boot-args for OpenCore-related flags */
    if (bootargs_has_opencore()) {
        flags |= OCLP_METHOD_BOOTARGS;
    }

    return flags;
}

char *oclp_describe(int detection_flags, char *buf, size_t buf_size)
{
    if (detection_flags == 0) {
        snprintf(buf, buf_size, "No OCLP detected");
        return buf;
    }

    buf[0] = '\0';
    size_t offset = 0;

    offset += snprintf(buf + offset, buf_size - offset, "OCLP detected via:");

    if (detection_flags & OCLP_METHOD_OPENCORE_DIR)
        offset += snprintf(buf + offset, buf_size - offset, " [/Library/OpenCore]");
    if (detection_flags & OCLP_METHOD_NVRAM)
        offset += snprintf(buf + offset, buf_size - offset, " [NVRAM opencore-version]");
    if (detection_flags & OCLP_METHOD_DORTANIA_DIR)
        offset += snprintf(buf + offset, buf_size - offset, " [Dortania dir]");
    if (detection_flags & OCLP_METHOD_BOOTARGS)
        offset += snprintf(buf + offset, buf_size - offset, " [boot-args]");

    return buf;
}
