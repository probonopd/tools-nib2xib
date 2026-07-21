/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

@interface GormWriter : NSObject

- (instancetype) initWithContentsOfFile: (NSString *)path;
- (BOOL) writeToGorm: (NSString *)gormPath;

@end
