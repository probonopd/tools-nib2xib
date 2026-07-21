/* Copyright (C) 2024 Free Software Foundation, Inc.
 *
 * Author:      Gregory John Casamento <greg.casamento@gmail.com>
 * Date:        2024
 *
 * This file is part of GNUstep.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02111
 * USA.
 */

#import <Foundation/NSString.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSArray.h>
#import <AppKit/NSMatrix.h>

#import "NSMenuTemplate.h"
#import "XMLNode.h"
#import "NIBParser.h"

@implementation NSMenuTemplate (Methods)

- (NSString *) classNameForParser
{
    return @"NSMenu";
}

- (NSMutableDictionary *) attributesFromProperties: (id<OidProvider>) op
{
    NSString *ident = [op oidForObject: self];
    return [NSMutableDictionary dictionaryWithObjectsAndKeys:
                ident, @"id", nil];
}

- (XMLNode *) toXMLWithParser: (id<OidProvider>)parser
{
    NSMutableDictionary *attributes = [self attributesFromProperties: parser];
    XMLNode *node = [[XMLNode alloc] initWithName: @"menu" value: @"" attributes: attributes elements: nil];
    return node;
}

@end
