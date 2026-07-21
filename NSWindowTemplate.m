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

#import <AppKit/AppKit.h>

#import "NSWindowTemplate.h"
#import "XMLNode.h"
#import "NSString_Additions.h"
#import "NSObject_KeyExtraction.h"

@implementation NSWindowTemplate (Methods)

- (int) interfaceStyle
{
    return 0;
}

- (void) setInterfaceStyle:(int)fp16
{
}

- (NSMutableDictionary *) attributesFromProperties
{
    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    if ([self respondsToSelector: @selector(title)])
    {
        [result setObject: [self title] forKey: @"title"];
    }
    if ([self respondsToSelector: @selector(windowClass)])
    {
        if ([self respondsToSelector: @selector(className)])
        {
            [result setObject: [self className] forKey: @"customClass"];
        }
    }

    return result;
}

- (NSString *) classNameForParser
{
    return @"NSWindow";
}

- (XMLNode *) toXMLWithParser: (id<OidProvider>)parser
{
    NSString *oid = [parser oidForObject: self];
    NSRect wr = ([self respondsToSelector: @selector(windowRect)]) ? [self windowRect] : NSZeroRect;

    XMLNode *node = [[XMLNode alloc] initWithName: @"window"];
    XMLNode *frame = [XMLNode nodeForRect: wr type: @"contentRect"];
    id windowView = ([self respondsToSelector: @selector(view)]) ? [self view] : nil;
    XMLNode *viewNode = [[XMLNode alloc] initWithName: @"view"];
    NSString *title = ([self respondsToSelector: @selector(title)]) ? [self title] : nil;

    [node addAttribute: @"id" value: oid];
    if (title != nil)
    {
        [node addAttribute: @"title" value: title];
    }
    if ([self respondsToSelector: @selector(className)])
    {
        NSString *wc = [self className];
        if (wc != nil && [wc isEqualToString: @"NSWindow"] == NO)
        {
            [node addAttribute: @"customClass" value: wc];
        }
    }

    [viewNode addAttribute: @"id" value: [parser oidForObject: windowView]];
    [viewNode addAttribute: @"key" value: @"contentView"];

    [node addElement: frame];
    [node addElement: viewNode];

    return node;
}

@end
