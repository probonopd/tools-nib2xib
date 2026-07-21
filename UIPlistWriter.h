/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

@class NSIBObjectData;

@interface UIPlistWriter : NSObject

- (instancetype) initWithObjectData: (NSIBObjectData *)objectData;
- (NSString *) string;

@end
