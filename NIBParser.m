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

#import <Foundation/NSArchiver.h>
#import <Foundation/NSDictionary.h>

#import <GNUstepGUI/GSNibLoading.h>

#import "NSIBConnector.h"
#import "NSCustomObject.h"
#import "NSWindowTemplate.h"
#import "NSMenuTemplate.h"

#import "NIBParser.h"
#import "XMLDocument.h"
#import "XMLNode.h"

void PrintMapTable(NSMapTable *mt)
{
	NSArray *keys = NSAllMapTableKeys(mt);
	NSEnumerator *en = [keys objectEnumerator];
	id k = nil;

	while ((k = [en nextObject]) != nil)
	{
		id v = NSMapGet(mt, k);
		NSLog(@"k = %@, v = %@", k, v);
	}
}

@implementation NIBParser

- (id) initWithNibNamed: (NSString *)nibNamed
{
	self = [super init];
	if (self != nil)
	{
		NSString *keyedPath = [nibNamed stringByAppendingPathComponent: @"keyedobjects.nib"];
		NSData *data = [NSData dataWithContentsOfFile: keyedPath];

		_nameTable = NULL;
		_oidTable = NULL;
		_objectTable = NULL;

		if (data != nil)
		{
			NSKeyedUnarchiver *unarchiver;
			unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData: data];
			_object = [[unarchiver decodeObjectForKey: @"IB.objectdata"] retain];
			[unarchiver release];
		}

		if (_object == nil || [_object respondsToSelector: @selector(root)] == NO)
		{
			NSLog(@"Failed to decode nib: %@", nibNamed);
			[self release];
			return nil;
		}

		_rootObject = [_object root];
		_nameTable = ([_object respondsToSelector: @selector(names)]) ? (NSMapTable *)[_object names] : nil;
		_oidTable = ([_object respondsToSelector: @selector(oids)]) ? (NSMapTable *)[_object oids] : nil;
		_objectTable = ([_object respondsToSelector: @selector(objects)]) ? (NSMapTable *)[_object objects] : nil;
		_connections = ([_object respondsToSelector: @selector(connections)]) ? [_object connections] : nil;

		_objectsProcessed = NSCreateMapTable(NSNonRetainedObjectMapKeyCallBacks, NSObjectMapValueCallBacks, 0);
		_objectsDictionary = [NSMutableDictionary dictionary];
		_classesDictionary = [NSMutableDictionary dictionary];
	}
	return self;
}

- (void) addProcessedObject: (id)object withNode: node
{
	NSMapInsertIfAbsent(_objectsProcessed, object, node);
}

- (void) removeProcessedObject: (id)object
{
	NSMapRemove(_objectsProcessed, object);
}

- (BOOL) isObjectProcessed: (id)object
{
	if (NSMapGet(_objectsProcessed, object) != NULL)
	{
		return YES;
	}
	return NO;
}

- (NSArray *) objectsProcessed
{
	NSArray *keys = NSAllMapTableKeys(_objectsProcessed);
	NSMutableArray *result = [NSMutableArray array];
	NSEnumerator *en = [keys objectEnumerator];
	id k = nil;

	while ((k = [en nextObject]) != nil)
	{
		id v = NSMapGet(_objectsProcessed, k);
		if (v != NULL)
		{
			[result addObject: v];
		}
	}

	return result;
}

- (XMLNode *) processedObject: (id)object
{
	XMLNode *node = NSMapGet(_objectsProcessed, object);
	if (node != NULL)
	{
		return node;
	}
	return nil;
}

- (NSString *) oidForObject: (id)obj
{
	int n = 0;

	if (_oidTable != NULL)
	{
		void *v = NSMapGet(_oidTable, obj);
		if (v != NULL)
		{
			if ([(id)v isKindOfClass: [NSNumber class]])
			{
				n = [(NSNumber *)v intValue];
			}
			else
			{
				n = (int)(intptr_t)v;
			}
		}
	}

	if (n == 0)
	{
		n = (int)[obj hash];
	}

	NSString *value = nil;
	NSString *result = [NSString stringWithFormat: @"%08x", n];
	NSString *first = [result substringWithRange: NSMakeRange(0, 3)];
	NSString *middle = [result substringWithRange: NSMakeRange(3, 2)];
	NSString *last = [result substringWithRange: NSMakeRange(5, 3)];
	value = [NSString stringWithFormat: @"%@-%@-%@", first, middle, last];

	if ([value isEqualToString: @"000-00-000"])
	{
		value = @"-1";
	}
	else if ([value isEqualToString: @"000-00-001"])
	{
		value = @"-2";
	}

	return value;
}

- (NSString *) oidString
{
	static int n = 0xffff;
	NSString *result = [NSString stringWithFormat: @"%08x", n--];
	NSString *first = [result substringWithRange: NSMakeRange(0, 3)];
	NSString *middle = [result substringWithRange: NSMakeRange(3, 2)];
	NSString *last = [result substringWithRange: NSMakeRange(5, 3)];
	return [NSString stringWithFormat: @"%@-%@-%@", first, middle, last];
}

- (NSArray *) connectionsWithSource: (id)src
{
	NSEnumerator *en = [_connections objectEnumerator];
	NSMutableArray *result = [NSMutableArray array];
	NSNibConnector *c = nil;

	while ((c = [en nextObject]))
	{
		if ([c source] == src)
		{
			[result addObject: c];
		}
	}

	return result;
}

- (NSArray *) connectionsWithDestination: (id)dst
{
	NSEnumerator *en = [_connections objectEnumerator];
	NSMutableArray *result = [NSMutableArray array];
	NSNibConnector *c = nil;

	while ((c = [en nextObject]))
	{
		if ([c destination] == dst)
		{
			[result addObject: c];
		}
	}

	return result;
}

- (NSArray *) connectionsWithObject: (id)origin
{
	NSEnumerator *en = [_connections objectEnumerator];
	NSMutableArray *result = [NSMutableArray array];
	NSNibConnector *c = nil;

	while ((c = [en nextObject]))
	{
		if ([c isKindOfClass: [NSNibControlConnector class]])
		{
			if ([c source] == origin)
			{
				[result addObject: c];
			}
		}
		else if ([c isKindOfClass: [NSNibOutletConnector class]])
		{
			if ([c source] == origin)
			{
				[result addObject: c];
			}
		}
	}

	return result;
}

- (void) addConnectionsForObject: (id)obj
						  toNode: (XMLNode *)node
{
	XMLNode *connections = [[XMLNode alloc] initWithName: @"connections"];
	NSArray *conns = [self connectionsWithObject: obj];
	NSEnumerator *en = [conns objectEnumerator];
	id c = nil;

	while ((c = [en nextObject]))
	{
		XMLNode *cn = [c toXMLWithParser: self];
		[connections addElement: cn];
	}

	if ([conns count] > 0)
	{
		[node addElement: connections];
	}
}

- (id) parse
{
	NSArray *os = [NSArray arrayWithObjects: @"com.apple.InterfaceBuilder3.Cocoa.XIB",
		@"3.0", @"32700.99.1234", @"MacOSX.Cocoa", @"none", @"YES", @"direct", nil];
	NSArray *ks = [NSArray arrayWithObjects: @"type", @"version", @"toolsVersion",
		@"targetRuntime", @"propertyAccessControl", @"useAutolayout", @"customObjectInstantiationMethod", nil];
	NSMutableDictionary *docAttrs = [NSMutableDictionary dictionaryWithObjects: os forKeys: ks];
	XMLDocument *document = [[XMLDocument alloc] initWithName: @"document"];
	NSArray *nameTable = (_object != nil && [_object respondsToSelector: @selector(names)]) ? [_object names] : nil;
	NSArray *keys = [nameTable allKeys];
	NSEnumerator *en = [keys objectEnumerator];
	XMLNode *dependencies = [[XMLNode alloc] initWithName: @"dependencies"];
	XMLNode *deployment = [[XMLNode alloc] initWithName: @"deployment"];
	XMLNode *plugIn = [[XMLNode alloc] initWithName: @"plugIn"];
	XMLNode *capability = [[XMLNode alloc] initWithName: @"capability"];
	XMLNode *objects = [[XMLNode alloc] initWithName: @"objects"];
	XMLNode *firstResponder = [[XMLNode alloc] initWithName: @"customObject"];
	XMLNode *applicationPlaceholder = [[XMLNode alloc] initWithName: @"customObject"];
	id o = nil;

	[document setAttributes: docAttrs];
	[deployment addAttribute: @"identifier" value: @"macosx"];
	[plugIn addAttribute: @"identifier" value: @"com.apple.InterfaceBuilder.CocoaPlugin"];
	[plugIn addAttribute: @"version" value: @"22690"];
	[capability addAttribute: @"name" value: @"documents saved in the Xcode 8 format"];
	[capability addAttribute: @"minToolsVersion" value: @"8.0"];
	[dependencies addElement: deployment];
	[dependencies addElement: plugIn];
	[dependencies addElement: capability];
	[document addElement: dependencies];
	[document addElement: objects];

	while ((o = [en nextObject]) != nil)
	{
		NSString *label = NSMapGet(nameTable, o);

		if ([o isKindOfClass: [NSCustomObject class]])
		{
			XMLNode *co = [o toXMLWithParser: self];
			[co addAttribute:@"userLabel" value: label];
			[objects addElement: co];
			[self addConnectionsForObject: o toNode: co];
		}
		else if ([o isKindOfClass: [NSMenuTemplate class]])
		{
			XMLNode *menu = [o toXMLWithParser: self];
			[menu addAttribute: @"title" value: @"Main Menu"];
			[menu addAttribute: @"systemMenu" value: @"main"];
			[objects addElement: menu];
			[self addConnectionsForObject: o toNode: menu];
		}
		else
		{
			NSLog(@"Unknown class: %@", o);
		}
	}

	if (_connections != nil)
	{
		for (id c in _connections)
		{
			id dst = [c destination];
			id src = [c source];
			for (id target in [NSArray arrayWithObjects: dst, src, nil])
			{
				if ([target isKindOfClass: [NSWindowTemplate class]]
				 && [self isObjectProcessed: target] == NO)
				{
					XMLNode *window = [target toXMLWithParser: self];
					[objects addElement: window];
					[self addConnectionsForObject: target toNode: window];
				}
			}
		}
	}

	[firstResponder addAttribute: @"customClass" value: @"FirstResponder"];
	[firstResponder addAttribute: @"userLabel" value: @"First Responder"];
	[firstResponder addAttribute: @"id" value: @"-1"];
	[objects addElement: firstResponder];

	[applicationPlaceholder addAttribute: @"customClass" value: @"NSApplication"];
	[applicationPlaceholder addAttribute: @"userLabel" value: @"Application"];
	[applicationPlaceholder addAttribute: @"id" value: @"-3"];
	[objects addElement: applicationPlaceholder];

	return document;
}

@end
