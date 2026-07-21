/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "UIPlistWriter.h"
#import "NSIBObjectData.h"

static BOOL isInlineClass(Class cls)
{
  if (cls == nil) return YES;
  if (cls == [NSString class] || cls == [NSMutableString class]) return YES;
  if (cls == [NSNumber class]) return YES;
  if (cls == [NSData class] || cls == [NSMutableData class]) return YES;
  if (cls == [NSArray class] || cls == [NSMutableArray class]) return YES;
  if (cls == [NSDictionary class] || cls == [NSMutableDictionary class]) return YES;
  if (cls == [NSValue class]) return YES;
  if (cls == [NSDate class]) return YES;
  return NO;
}

// Returns YES if the object's description contains a runtime pointer address (0x...)
// indicating it is an ephemeral runtime artifact, not an archived value.
static BOOL hasPointerDescription(id obj)
{
  NSString *desc = [obj description];
  if (desc == nil) return NO;
  return ([desc rangeOfString: @"0x[0-9a-f]+" options: NSRegularExpressionSearch].location != NSNotFound);
}

static NSSet *skippedPropertyNames(void)
{
  static NSMutableSet *set = nil;
  if (set == nil)
  {
    set = [[NSMutableSet alloc] initWithObjects:
      @"hash", @"superclass", @"description", @"debugDescription",
      @"class", @"self", @"zone", @"proxy", @"isProxy",
      @"retainCount", @"observationInfo",
      nil];
  }
  return set;
}

@interface UIPlistWriter ()
{
  NSIBObjectData *_objectData;
  NSMapTable *_oids;       // object -> NSNumber(oid)
  NSMutableDictionary *_oidToObject;  // oid -> object
}
@end

@implementation UIPlistWriter

- (instancetype) initWithObjectData: (NSIBObjectData *)objectData
{
  self = [super init];
  if (self)
  {
    _objectData = [objectData retain];
    _oids = [[_objectData oids] retain];
    _oidToObject = [[NSMutableDictionary alloc] init];

    NSArray *keys = NSAllMapTableKeys(_oids);
    for (id obj in keys)
    {
      id val = NSMapGet(_oids, (__bridge void *)obj);
      NSNumber *oidNum = nil;
      if ([val isKindOfClass: [NSNumber class]])
        oidNum = val;
      else
        oidNum = [NSNumber numberWithInt: (int)(intptr_t)val];
      [_oidToObject setObject: obj forKey: oidNum];
    }
  }
  return self;
}

- (void) dealloc
{
  [_objectData release];
  [_oids release];
  [_oidToObject release];
  [super dealloc];
}

- (NSString *) oidForObject: (id)obj
{
  if (obj == nil) return nil;
  void *val = NSMapGet(_oids, (__bridge void *)obj);
  if (val == NULL) return nil;
  int oid = 0;
  if ([(__bridge id)val isKindOfClass: [NSNumber class]])
    oid = [(__bridge NSNumber *)val intValue];
  else
    oid = (int)(intptr_t)val;
  return [NSString stringWithFormat: @"%d", oid];
}

- (BOOL) objectHasOid: (id)obj
{
  if (obj == nil) return NO;
  return (NSMapGet(_oids, (__bridge void *)obj) != NULL);
}

- (NSString *) quoteString: (NSString *)str
{
  NSMutableString *result = [NSMutableString stringWithString: @"\""];
  for (NSUInteger i = 0; i < [str length]; i++)
  {
    unichar c = [str characterAtIndex: i];
    switch (c)
    {
      case '"':  [result appendString: @"\\\""]; break;
      case '\\': [result appendString: @"\\\\"]; break;
      case '\n': [result appendString: @"\\n"]; break;
      case '\r': [result appendString: @"\\r"]; break;
      case '\t': [result appendString: @"\\t"]; break;
      default:
        if (c < 0x20)
          [result appendFormat: @"\\U%04x", (unsigned int)c];
        else
          [result appendFormat: @"%C", c];
        break;
    }
  }
  [result appendString: @"\""];
  return result;
}

- (NSString *) valueString: (id)value indent: (int)indent
{
  if (value == nil)
    return @"";

  // Object reference
  if ([self objectHasOid: value] && !isInlineClass([value class]))
  {
    NSString *oid = [self oidForObject: value];
    return [NSString stringWithFormat: @"@%@", oid];
  }

  // String
  if ([value isKindOfClass: [NSString class]])
    return [self quoteString: (NSString *)value];

  // Number
  if ([value isKindOfClass: [NSNumber class]])
  {
    NSNumber *num = (NSNumber *)value;
    const char *type = [num objCType];
    if (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(char)) == 0)
      return [num boolValue] ? @"YES" : @"NO";
    if (strcmp(type, @encode(float)) == 0 || strcmp(type, @encode(double)) == 0)
      return [NSString stringWithFormat: @"%@", num];
    return [NSString stringWithFormat: @"%ld", (long)[num integerValue]];
  }

  // Data
  if ([value isKindOfClass: [NSData class]])
  {
    NSData *data = (NSData *)value;
    NSUInteger len = [data length];
    const unsigned char *bytes = [data bytes];
    NSMutableString *hex = [NSMutableString stringWithString: @"<"];
    for (NSUInteger i = 0; i < len; i++)
      [hex appendFormat: @"%02x", bytes[i]];
    [hex appendString: @">"];
    return hex;
  }

  // Date
  if ([value isKindOfClass: [NSDate class]])
  {
    return [self quoteString: [value description]];
  }

  // Value (NSRect, NSPoint, NSSize, etc.)
  if ([value isKindOfClass: [NSValue class]])
  {
    return [self quoteString: [value description]];
  }

  // Array
  if ([value isKindOfClass: [NSArray class]])
  {
    NSArray *arr = (NSArray *)value;
    if ([arr count] == 0) return @"()";
    NSString *indentStr = [NSString stringWithFormat: @"%*s", (indent + 1) * 4, ""];
    NSString *innerIndent = [NSString stringWithFormat: @"%*s", (indent + 2) * 4, ""];
    NSMutableString *result = [NSMutableString stringWithString: @"(\n"];
    for (id item in arr)
    {
      [result appendFormat: @"%@%@", innerIndent, [self valueString: item indent: indent + 1]];
      [result appendString: @",\n"];
    }
    [result appendFormat: @"%@)", indentStr];
    return result;
  }

  // Dictionary
  if ([value isKindOfClass: [NSDictionary class]])
  {
    NSDictionary *dict = (NSDictionary *)value;
    if ([dict count] == 0) return @"{}";
    NSString *indentStr = [NSString stringWithFormat: @"%*s", (indent + 1) * 4, ""];
    NSString *innerIndent = [NSString stringWithFormat: @"%*s", (indent + 2) * 4, ""];
    NSMutableString *result = [NSMutableString stringWithString: @"{\n"];
    for (id key in dict)
    {
      [result appendFormat: @"%@%@ = %@;\n",
        innerIndent,
        [self quoteString: [key description]],
        [self valueString: [dict objectForKey: key] indent: indent + 1]];
    }
    [result appendFormat: @"%@}", indentStr];
    return result;
  }

  // Fallback: describe
  return [self quoteString: [value description]];
}

- (NSDictionary *) propertiesForObject: (id)obj
{
  NSMutableDictionary *props = [NSMutableDictionary dictionary];
  Class cls = [obj class];

  // Collect all properties from the class hierarchy
  while (cls != nil && cls != [NSObject class] && cls != [NSProxy class])
  {
    unsigned int count = 0;
    objc_property_t *propertyList = class_copyPropertyList(cls, &count);
    for (unsigned int i = 0; i < count; i++)
    {
      const char *name = property_getName(propertyList[i]);
      NSString *key = [NSString stringWithUTF8String: name];
      if ([skippedPropertyNames() containsObject: key])
        continue;
      @try
      {
        id val = [obj valueForKey: key];
        if (val != nil)
        {
          // Skip ephemeral runtime-only values (contain pointer addresses)
          // unless they have a known oid (i.e. are part of the archive)
          if (hasPointerDescription(val) && ![self objectHasOid: val])
            continue;
          [props setObject: val forKey: key];
        }
      }
      @catch (NSException *e)
      {
        // skip
      }
    }
    free(propertyList);

    // Also get ivars
    unsigned int ivarCount = 0;
    Ivar *ivarList = class_copyIvarList(cls, &ivarCount);
    for (unsigned int i = 0; i < ivarCount; i++)
    {
      const char *name = ivar_getName(ivarList[i]);
      NSString *key = [NSString stringWithUTF8String: name];
      if ([key hasPrefix: @"_"])
        key = [key substringFromIndex: 1];
      if ([skippedPropertyNames() containsObject: key])
        continue;
      if ([props objectForKey: key] != nil)
        continue;  // already got from property
      @try
      {
        id val = [obj valueForKey: key];
        if (val != nil)
        {
          if (hasPointerDescription(val) && ![self objectHasOid: val])
            continue;
          [props setObject: val forKey: key];
        }
      }
      @catch (NSException *e)
      {
        // skip
      }
    }
    free(ivarList);

    cls = class_getSuperclass(cls);
  }

  return props;
}

- (NSString *) serializeObject: (id)obj indent: (int)indent
{
  NSString *indentStr = [NSString stringWithFormat: @"%*s", indent * 4, ""];
  NSString *innerIndent = [NSString stringWithFormat: @"%*s", (indent + 1) * 4, ""];
  NSString *deepIndent = [NSString stringWithFormat: @"%*s", (indent + 2) * 4, ""];

  NSString *oid = [self oidForObject: obj];
  NSString *className = NSStringFromClass([obj class]);

  NSMutableString *result = [NSMutableString string];
  [result appendFormat: @"%@{\n", indentStr];

  if (oid)
    [result appendFormat: @"%@id = %@;\n", innerIndent, oid];
  [result appendFormat: @"%@isa = %@;\n", innerIndent, className];

  NSDictionary *props = [self propertiesForObject: obj];
  if ([props count] > 0)
  {
    [result appendFormat: @"%@keys =\n", innerIndent];
    [result appendFormat: @"%@{\n", innerIndent];
    NSArray *sortedKeys = [[props allKeys] sortedArrayUsingSelector: @selector(compare:)];
    for (NSString *key in sortedKeys)
    {
      id val = [props objectForKey: key];
      [result appendFormat: @"%@%@ = %@;\n",
        deepIndent, key, [self valueString: val indent: indent + 2]];
    }
    [result appendFormat: @"%@};\n", innerIndent];
  }

  [result appendFormat: @"%@}", indentStr];
  return result;
}

- (NSString *) string
{
  NSMapTable *objects = [_objectData oids];
  NSArray *allObjects = NSAllMapTableKeys(objects);

  NSMutableString *result = [NSMutableString string];

  [result appendString: @"{\n"];
  [result appendString: @"    version = 1;\n\n"];
  [result appendString: @"    archive =\n"];
  [result appendString: @"    {\n"];

  // Root
  id root = [_objectData root];
  NSString *rootOid = [self oidForObject: root];
  if (rootOid)
    [result appendFormat: @"        root = @%@;\n\n", rootOid];
  else
    [result appendString: @"        root = 0;\n\n"];

  // Objects array - list all non-inline objects that have oids
  NSMutableArray *sortedObjects = [NSMutableArray array];
  for (id obj in allObjects)
  {
    if (!isInlineClass([obj class]))
      [sortedObjects addObject: obj];
  }
  [sortedObjects sortUsingComparator: ^NSComparisonResult(id a, id b) {
    NSString *oidA = [self oidForObject: a];
    NSString *oidB = [self oidForObject: b];
    if (oidA == nil && oidB == nil) return NSOrderedSame;
    if (oidA == nil) return NSOrderedDescending;
    if (oidB == nil) return NSOrderedAscending;
    int na = [oidA intValue];
    int nb = [oidB intValue];
    if (na < nb) return NSOrderedAscending;
    if (na > nb) return NSOrderedDescending;
    return NSOrderedSame;
  }];
  [result appendString: @"        objects = (\n"];
  for (id obj in sortedObjects)
  {
    NSString *objStr = [self serializeObject: obj indent: 5];
    [result appendFormat: @"%@", objStr];
    [result appendString: @",\n"];
  }
  [result appendString: @"        );\n"];
  [result appendString: @"    };\n"];
  [result appendString: @"}\n"];

  return result;
}

@end
