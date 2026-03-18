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

#ifndef OCLP_DETECT_H
#define OCLP_DETECT_H

#include <stdbool.h>

/*
 * OCLP detection methods (bitfield flags for reporting which triggered):
 *   0x01 = /Library/OpenCore directory exists
 *   0x02 = NVRAM opencore-version key present
 *   0x04 = /Library/Application Support/Dortania directory exists
 *   0x08 = OpenCore boot-args detected
 */
#define OCLP_METHOD_OPENCORE_DIR   0x01
#define OCLP_METHOD_NVRAM          0x02
#define OCLP_METHOD_DORTANIA_DIR   0x04
#define OCLP_METHOD_BOOTARGS       0x08

/*
 * Check if this Mac is running OpenCore Legacy Patcher.
 *
 * Returns: bitfield of detection methods that matched, or 0 if not OCLP.
 *          Any non-zero value means OCLP was detected.
 */
int oclp_detect(void);

/*
 * Human-readable description of detection results.
 * Writes to the provided buffer. Returns the buffer pointer.
 */
char *oclp_describe(int detection_flags, char *buf, size_t buf_size);

#endif /* OCLP_DETECT_H */
