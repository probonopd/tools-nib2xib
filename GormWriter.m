/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "GormWriter.h"
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <GNUstepGUI/GSGormLoading.h>

static NSString *const OidRefPrefix = @"__oidref_";
static NSString *const OidRefSuffix = @"__";

static int extractOid(NSString *str)
{
  if ([str hasPrefix: OidRefPrefix] && [str hasSuffix: OidRefSuffix])
    {
      NSUInteger plen = [OidRefPrefix length];
      NSUInteger slen = [OidRefSuffix length];
      NSString *num = [str substringWithRange: NSMakeRange(plen,
        [str length] - plen - slen)];
      return [num intValue];
    }
  return 0;
}

@interface GormWriter ()
{
  NSString *_path;
  NSDictionary *_parsedPlist;
  NSArray *_sortedObjects;
  NSMutableDictionary *_oidToObject;   // oid (NSNumber) -> instantiated object
  NSMutableArray *_allInstances;       // ordered instances matching _sortedObjects
}
@end

@implementation GormWriter

- (instancetype) initWithContentsOfFile: (NSString *)path
{
  self = [super init];
  if (self)
    {
      _path = [path copy];
      _parsedPlist = nil;
      _sortedObjects = nil;
      _oidToObject = [[NSMutableDictionary alloc] init];
      _allInstances = [[NSMutableArray alloc] init];
    }
  return self;
}

- (void) dealloc
{
  [_path release];
  [_parsedPlist release];
  [_sortedObjects release];
  [_oidToObject release];
  [_allInstances release];
  [super dealloc];
}

- (BOOL) _parsePlist
{
  NSString *content = [NSString stringWithContentsOfFile: _path
                                                encoding: NSUTF8StringEncoding
                                                   error: NULL];
  if (content == nil) return NO;

  NSRegularExpression *regex = [NSRegularExpression
    regularExpressionWithPattern: @"@(\\d+)"
    options: 0 error: NULL];
  NSString *processed = [regex stringByReplacingMatchesInString: content
    options: 0 range: NSMakeRange(0, [content length])
    withTemplate: @"\"__oidref_$1__\""];
  if (processed == nil) return NO;

  NSData *data = [processed dataUsingEncoding: NSUTF8StringEncoding];
  if (data == nil) return NO;

  NSString *err = nil;
  id plist = [NSPropertyListSerialization propertyListFromData: data
    mutabilityOption: NSPropertyListImmutable format: NULL
    errorDescription: &err];
  if (plist == nil) return NO;

  _parsedPlist = (NSDictionary *)[plist retain];
  return YES;
}

- (BOOL) _instantiateObjects
{
  NSDictionary *archive = [_parsedPlist objectForKey: @"archive"];
  if (archive == nil) return NO;

  NSArray *objects = [archive objectForKey: @"objects"];
  if (objects == nil) return NO;

  _sortedObjects = [[objects sortedArrayUsingComparator: ^NSComparisonResult(id a, id b) {
    int ia = [[(NSDictionary *)a objectForKey: @"id"] intValue];
    int ib = [[(NSDictionary *)b objectForKey: @"id"] intValue];
    if (ia < ib) return NSOrderedAscending;
    if (ia > ib) return NSOrderedDescending;
    return NSOrderedSame;
  }] retain];

  // Pass 1: instantiate all objects
  for (NSDictionary *objDict in _sortedObjects)
    {
      NSString *clsName = [objDict objectForKey: @"isa"];
      NSNumber *oid = [objDict objectForKey: @"id"];
      id instance = nil;

      Class cls = NSClassFromString(clsName);
      if (cls != nil)
        {
          NS_DURING
            instance = [[cls alloc] init];
          NS_HANDLER
            NSLog(@"Failed to init %@ (oid %@): %@", clsName, oid, [localException reason]);
            instance = [[NSObject alloc] init];
          NS_ENDHANDLER
        }
      else
        {
          NSLog(@"Unknown class %@ (oid %@), using NSObject", clsName, oid);
          instance = [[NSObject alloc] init];
        }

      if (instance)
        {
          [_oidToObject setObject: instance forKey: oid];
          [_allInstances addObject: instance];
          [instance release]; // retained by dictionaries/arrays
        }
    }

  // Pass 2: resolve @oid refs and set properties via KVC
  for (NSDictionary *objDict in _sortedObjects)
    {
      NSNumber *oid = [objDict objectForKey: @"id"];
      id instance = [_oidToObject objectForKey: oid];
      if (instance == nil) continue;

      NSDictionary *keys = [objDict objectForKey: @"keys"];
      if (keys == nil) continue;

      for (NSString *key in keys)
        {
          id val = [keys objectForKey: key];
          id resolved = [self _resolveValue: val];
          if (resolved != nil)
            {
              NS_DURING
                [instance setValue: resolved forKey: key];
              NS_HANDLER
                // skip
              NS_ENDHANDLER
            }
        }
    }

  return YES;
}

- (id) _resolveValue: (id)value
{
  if (value == nil) return nil;

  if ([value isKindOfClass: [NSString class]])
    {
      NSString *str = (NSString *)value;
      if ([str hasPrefix: OidRefPrefix] && [str hasSuffix: OidRefSuffix])
        {
          int oid = extractOid(str);
          return [_oidToObject objectForKey: [NSNumber numberWithInt: oid]];
        }

      NSScanner *sc = [NSScanner scannerWithString: str];
      long long ll;
      double d;
      if ([sc scanLongLong: &ll] && [sc isAtEnd])
        return [NSNumber numberWithLongLong: ll];
      [sc setScanLocation: 0];
      if ([sc scanDouble: &d] && [sc isAtEnd])
        return [NSNumber numberWithDouble: d];
      return str;
    }

  if ([value isKindOfClass: [NSNumber class]]) return value;
  if ([value isKindOfClass: [NSData class]]) return value;

  if ([value isKindOfClass: [NSArray class]])
    {
      NSMutableArray *result = [NSMutableArray array];
      for (id item in (NSArray *)value)
        {
          id r = [self _resolveValue: item];
          if (r) [result addObject: r];
        }
      return result;
    }

  if ([value isKindOfClass: [NSDictionary class]])
    {
      NSMutableDictionary *result = [NSMutableDictionary dictionary];
      for (id key in [(NSDictionary *)value allKeys])
        {
          id r = [self _resolveValue: [(NSDictionary *)value objectForKey: key]];
          if (r) [result setObject: r forKey: key];
        }
      return result;
    }

  return value;
}

- (BOOL) writeToGorm: (NSString *)gormPath
{
  if (![self _parsePlist]) return NO;
  if (![self _instantiateObjects]) return NO;

  // Build nameTable (NSString name -> id object)
  NSMutableDictionary *nameTable = [NSMutableDictionary dictionary];
  for (NSDictionary *objDict in _sortedObjects)
    {
      NSNumber *oid = [objDict objectForKey: @"id"];
      id instance = [_oidToObject objectForKey: oid];
      if (instance)
        {
          NSString *name = [objDict objectForKey: @"isa"];
          [nameTable setObject: instance forKey: name];
        }
    }

  // Build connections array
  NSMutableArray *connections = [NSMutableArray array];
  for (NSDictionary *objDict in _sortedObjects)
    {
      NSString *clsName2 = [objDict objectForKey: @"isa"];
      NSDictionary *keys = [objDict objectForKey: @"keys"];
      if ([clsName2 isEqualToString: @"NSNibOutletConnector"])
        {
          id src = [self _resolveValue: [keys objectForKey: @"source"]];
          id dst = [self _resolveValue: [keys objectForKey: @"destination"]];
          NSString *label = [keys objectForKey: @"label"];
          if (src && dst)
            {
              NSNibOutletConnector *c = [[NSNibOutletConnector alloc] init];
              [c setSource: src];
              [c setDestination: dst];
              if (label) [c setLabel: label];
              [connections addObject: c];
              [c release];
            }
        }
      else if ([clsName2 isEqualToString: @"NSNibControlConnector"])
        {
          id src = [self _resolveValue: [keys objectForKey: @"source"]];
          id dst = [self _resolveValue: [keys objectForKey: @"destination"]];
          NSString *label = [keys objectForKey: @"label"];
          if (src && dst)
            {
              NSNibControlConnector *c = [[NSNibControlConnector alloc] init];
              [c setSource: src];
              [c setDestination: dst];
              if (label) [c setLabel: label];
              [connections addObject: c];
              [c release];
            }
        }
    }

  // Create GSNibContainer
  GSNibContainer *container = [[GSNibContainer alloc] init];
  NS_DURING
    [container setValue: nameTable forKey: @"nameTable"];
    [container setValue: connections forKey: @"connections"];
  NS_HANDLER
    NSLog(@"Failed to set container properties: %@", [localException reason]);
    [container release];
    return NO;
  NS_ENDHANDLER

  // Archive with NSArchiver (binary format)
  NSData *archiveData = [NSArchiver archivedDataWithRootObject: container];
  [container release];

  if (archiveData == nil) return NO;

  // Create .gorm bundle directory
  NSFileManager *fm = [NSFileManager defaultManager];
  BOOL isDir = NO;
  if ([fm fileExistsAtPath: gormPath isDirectory: &isDir])
    {
      if (!isDir) return NO;
    }
  else
    {
      if (![fm createDirectoryAtPath: gormPath
         withIntermediateDirectories: YES attributes: nil error: NULL])
        return NO;
    }

  // Write objects.gorm
  NSString *objPath = [gormPath stringByAppendingPathComponent: @"objects.gorm"];
  if (![archiveData writeToFile: objPath atomically: YES])
    return NO;

  // Write data.classes
  NSMutableDictionary *classesDict = [NSMutableDictionary dictionary];
  for (NSDictionary *objDict in _sortedObjects)
    {
      NSString *clsName3 = [objDict objectForKey: @"isa"];
      if ([classesDict objectForKey: clsName3] == nil)
        {
          Class cls = NSClassFromString(clsName3);
          NSString *superName = @"NSObject";
          if (cls != nil)
            {
              Class superCls = class_getSuperclass(cls);
              if (superCls) superName = NSStringFromClass(superCls);
            }
          [classesDict setObject: [NSDictionary dictionaryWithObject: superName
            forKey: @"Super"] forKey: clsName3];
        }
    }

  NSString *err = nil;
  NSData *classesData = [NSPropertyListSerialization dataFromPropertyList: classesDict
    format: NSPropertyListOpenStepFormat errorDescription: &err];
  if (classesData)
    {
      NSString *cp = [gormPath stringByAppendingPathComponent: @"data.classes"];
      [classesData writeToFile: cp atomically: YES];
    }

  // Write data.info
  NSDictionary *infoDict = [NSDictionary dictionaryWithObjectsAndKeys:
    @"Gorm", @"application",
    @"0.1", @"applicationVersion",
    @"1", @"archiveVersion",
    nil];
  NSData *infoData = [NSPropertyListSerialization dataFromPropertyList: infoDict
    format: NSPropertyListOpenStepFormat errorDescription: NULL];
  if (infoData)
    {
      NSString *ip = [gormPath stringByAppendingPathComponent: @"data.info"];
      [infoData writeToFile: ip atomically: YES];
    }

  return YES;
}

@end
