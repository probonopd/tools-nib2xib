/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "UIPlistReader.h"
#import <objc/runtime.h>

static NSString *const OidRefPrefix = @"__oidref_";
static NSString *const OidRefSuffix = @"__";

static NSDictionary *makeCFSUID(NSUInteger index)
{
  return [NSDictionary dictionaryWithObject: [NSNumber numberWithUnsignedInteger: index]
                                     forKey: @"CF$UID"];
}



static id convertValue(id value, NSDictionary *oidToIndex)
{
  if (value == nil)
    return nil;

  if ([value isKindOfClass: [NSString class]])
    {
      NSString *str = (NSString *)value;

      // OpenStep plist may return numeric values as strings; convert back
      if (![str hasPrefix: OidRefPrefix])
        {
          NSScanner *sc = [NSScanner scannerWithString: str];
          long long ll;
          double d;
          if ([sc scanLongLong: &ll] && [sc isAtEnd])
            return [NSNumber numberWithLongLong: ll];
          [sc setScanLocation: 0];
          if ([sc scanDouble: &d] && [sc isAtEnd])
            return [NSNumber numberWithDouble: d];
        }

      if ([str hasPrefix: OidRefPrefix] && [str hasSuffix: OidRefSuffix])
        {
          NSUInteger prefixLen = [OidRefPrefix length];
          NSUInteger suffixLen = [OidRefSuffix length];
          NSString *numStr = [str substringWithRange: NSMakeRange(prefixLen, [str length] - prefixLen - suffixLen)];
          int oid = [numStr intValue];
          NSNumber *index = [oidToIndex objectForKey: [NSNumber numberWithInt: oid]];
          if (index)
            return makeCFSUID([index unsignedIntegerValue]);
          return makeCFSUID(0);
        }
      return value;
    }

  if ([value isKindOfClass: [NSNumber class]])
    return value;

  if ([value isKindOfClass: [NSData class]])
    return value;

  if ([value isKindOfClass: [NSArray class]])
    {
      NSMutableArray *result = [NSMutableArray array];
      for (id item in (NSArray *)value)
        {
          id converted = convertValue(item, oidToIndex);
          if (converted)
            [result addObject: converted];
        }
      return result;
    }

  if ([value isKindOfClass: [NSDictionary class]])
    {
      NSMutableDictionary *result = [NSMutableDictionary dictionary];
      for (id key in [(NSDictionary *)value allKeys])
        {
          id converted = convertValue([(NSDictionary *)value objectForKey: key], oidToIndex);
          if (converted)
            [result setObject: converted forKey: key];
        }
      return result;
    }

  return value;
}

static int extractOid(NSString *str)
{
  if ([str hasPrefix: OidRefPrefix] && [str hasSuffix: OidRefSuffix])
    {
      NSUInteger prefixLen = [OidRefPrefix length];
      NSUInteger suffixLen = [OidRefSuffix length];
      NSString *numStr = [str substringWithRange: NSMakeRange(prefixLen, [str length] - prefixLen - suffixLen)];
      return [numStr intValue];
    }
  return 0;
}

@interface UIPlistReader ()
{
  NSString *_path;
  NSDictionary *_parsedPlist;
  NSArray *_sortedObjects;
  NSMutableDictionary *_oidToIndex;
  NSMutableArray *_objectsArray;
  NSMutableDictionary *_classDefs;
}
@end

@implementation UIPlistReader

- (instancetype) initWithContentsOfFile: (NSString *)path
{
  self = [super init];
  if (self)
    {
      _path = [path copy];
      _parsedPlist = nil;
      _sortedObjects = nil;
      _oidToIndex = [[NSMutableDictionary alloc] init];
      _objectsArray = nil;
      _classDefs = [[NSMutableDictionary alloc] init];
    }
  return self;
}

- (void) dealloc
{
  [_path release];
  [_parsedPlist release];
  [_sortedObjects release];
  [_oidToIndex release];
  [_objectsArray release];
  [_classDefs release];
  [super dealloc];
}

- (BOOL) _parsePlist
{
  NSString *content = [NSString stringWithContentsOfFile: _path
                                                encoding: NSUTF8StringEncoding
                                                   error: NULL];
  if (content == nil)
    return NO;

  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern: @"@(\\d+)"
                                                                         options: 0
                                                                           error: NULL];
  if (regex == nil)
    return NO;

  NSString *processed = [regex stringByReplacingMatchesInString: content
                                                        options: 0
                                                          range: NSMakeRange(0, [content length])
                                                   withTemplate: @"\"__oidref_$1__\""];
  if (processed == nil)
    return NO;

  NSData *data = [processed dataUsingEncoding: NSUTF8StringEncoding];
  if (data == nil)
    return NO;

  NSString *errorDesc = nil;
  id plist = [NSPropertyListSerialization propertyListFromData: data
                                             mutabilityOption: NSPropertyListImmutable
                                                       format: NULL
                                             errorDescription: &errorDesc];
  if (plist == nil)
    return NO;

  _parsedPlist = (NSDictionary *)[plist retain];
  return YES;
}

- (BOOL) _buildObjectsArray
{
  NSDictionary *archive = [_parsedPlist objectForKey: @"archive"];
  if (archive == nil)
    return NO;

  id rootVal = [archive objectForKey: @"root"];
  int rootOid = 0;
  if ([rootVal isKindOfClass: [NSString class]])
    rootOid = extractOid((NSString *)rootVal);
  else if ([rootVal isKindOfClass: [NSNumber class]])
    rootOid = [(NSNumber *)rootVal intValue];

  NSArray *objects = [archive objectForKey: @"objects"];
  if (objects == nil)
    return NO;

  _sortedObjects = [[objects sortedArrayUsingComparator: ^NSComparisonResult(id a, id b) {
    int idA = [[(NSDictionary *)a objectForKey: @"id"] intValue];
    int idB = [[(NSDictionary *)b objectForKey: @"id"] intValue];
    if (idA < idB) return NSOrderedAscending;
    if (idA > idB) return NSOrderedDescending;
    return NSOrderedSame;
  }] retain];

  NSUInteger userCount = [_sortedObjects count];
  NSUInteger arrayCount = 14; // 13 NS-prefixed arrays + 1 frameworks string

  // Collect all unique class names
  NSMutableSet *classNames = [NSMutableSet set];
  [classNames addObject: @"NSIBObjectData"];
  [classNames addObject: @"NSMutableArray"];
  for (NSDictionary *objDict in _sortedObjects)
    {
      NSString *clsName = [objDict objectForKey: @"isa"];
      if (clsName)
        [classNames addObject: clsName];
    }
  NSArray *sortedClasses = [[classNames allObjects] sortedArrayUsingSelector: @selector(compare:)];
  NSUInteger classCount = [sortedClasses count];

  // Pre-computed $objects layout:
  // 0: $null
  // 1: NSIBObjectData (filled at end)
  // 2..(2+userCount-1): user objects
  // (2+userCount)..(2+userCount+arrayCount-1): array entries
  // (2+userCount+arrayCount)..: class definitions
  NSUInteger userStart = 2;
  NSUInteger arrayStart = userStart + userCount;
  NSUInteger classStart = arrayStart + arrayCount;

  // Pre-populate _classDefs with known indices
  NSUInteger ci = classStart;
  for (NSString *className in sortedClasses)
    {
      [_classDefs setObject: [NSNumber numberWithUnsignedInteger: ci] forKey: className];
      ci++;
    }

  // Build oid → $objects index mapping (use integer keys to avoid NSNumber type mismatch)
  NSUInteger userIdx = userStart;
  for (NSDictionary *objDict in _sortedObjects)
    {
      NSNumber *oid = [objDict objectForKey: @"id"];
      int oidInt = [oid intValue];
      [_oidToIndex setObject: [NSNumber numberWithUnsignedInteger: userIdx]
                      forKey: [NSNumber numberWithInt: oidInt]];
      userIdx++;
    }



  // Initialize $objects with placeholders
  _objectsArray = [[NSMutableArray alloc] init];
  NSUInteger totalSize = 1 + 1 + userCount + arrayCount + classCount;
  for (NSUInteger i = 0; i < totalSize; i++)
    [_objectsArray addObject: [NSNull null]];
  [_objectsArray replaceObjectAtIndex: 0 withObject: @"$null"];

  // Build array data for NSIBObjectData's NS-prefixed keys
  NSMutableArray *oidsKeys = [NSMutableArray array];
  NSMutableArray *oidsValues = [NSMutableArray array];
  NSMutableArray *objectsKeys = [NSMutableArray array];
  NSMutableArray *objectsValues = [NSMutableArray array];
  NSMutableArray *namesKeys = [NSMutableArray array];
  NSMutableArray *namesValues = [NSMutableArray array];

  int maxOid = 0;
  for (NSDictionary *objDict in _sortedObjects)
    {
      NSNumber *oid = [objDict objectForKey: @"id"];
      int oidInt = [oid intValue];
      if (oidInt > maxOid) maxOid = oidInt;

      NSNumber *index = [_oidToIndex objectForKey: [NSNumber numberWithInt: oidInt]];
      NSDictionary *ref = makeCFSUID([index unsignedIntegerValue]);

      [oidsKeys addObject: ref];
      [oidsValues addObject: [NSNumber numberWithInt: oidInt]];
      [objectsKeys addObject: ref];
      [objectsValues addObject: ref];
      [namesKeys addObject: ref];

      NSString *clsName = [objDict objectForKey: @"isa"];
      [namesValues addObject: clsName ? clsName : @""];
    }

  // Fill user objects at slots [userStart..userStart+userCount-1]
  NSUInteger obIdx = userStart;
  for (NSDictionary *objDict in _sortedObjects)
    {
      NSString *clsName = [objDict objectForKey: @"isa"];
      NSDictionary *keys = [objDict objectForKey: @"keys"];
      NSNumber *classIdx = [_classDefs objectForKey: clsName];

      NSMutableDictionary *entry = [NSMutableDictionary dictionary];
      [entry setObject: makeCFSUID([classIdx unsignedIntegerValue]) forKey: @"$class"];

      if (keys)
        {
          for (NSString *key in keys)
            {
              id val = [keys objectForKey: key];
              id converted = convertValue(val, _oidToIndex);
              if (converted)
                [entry setObject: converted forKey: key];
            }
        }
      [_objectsArray replaceObjectAtIndex: obIdx withObject: entry];
      obIdx++;
    }

  // Fill array entries at slots [arrayStart..arrayStart+arrayCount-1]
  NSUInteger ai = arrayStart;
  NSNumber *arrClassIdx = [_classDefs objectForKey: @"NSMutableArray"];
  NSArray *allArrData[] = {
    oidsKeys, oidsValues, objectsKeys, objectsValues,
    namesKeys, namesValues,
    [NSArray array], [NSArray array], [NSArray array], [NSArray array],
    [NSArray array], [NSArray array], [NSArray array]
  };
  for (int i = 0; i < 13; i++)
    {
      NSMutableDictionary *aEntry = [NSMutableDictionary dictionary];
      [aEntry setObject: makeCFSUID([arrClassIdx unsignedIntegerValue]) forKey: @"$class"];
      if ([allArrData[i] count] > 0)
        [aEntry setObject: allArrData[i] forKey: @"NS.objects"];
      [_objectsArray replaceObjectAtIndex: ai withObject: aEntry];
      ai++;
    }

  // Frameworks string
  [_objectsArray replaceObjectAtIndex: ai withObject: @"IBCocoaFramework"];
  NSUInteger frameworksIdx = ai;
  ai++;

  // Fill class definitions at slots [classStart..]
  for (NSString *className in sortedClasses)
    {
      // Build full class hierarchy using runtime introspection
      NSMutableArray *hierarchy = [NSMutableArray array];
      [hierarchy addObject: className];
      Class cls = NSClassFromString(className);
      if (cls != nil)
        {
          while ((cls = class_getSuperclass(cls)) != nil)
            [hierarchy addObject: NSStringFromClass(cls)];
        }
      else
        {
          // Fallback for unknown classes
          [hierarchy addObject: @"NSObject"];
        }

      NSMutableDictionary *classDict = [NSMutableDictionary dictionary];
      [classDict setObject: hierarchy forKey: @"$classes"];
      [classDict setObject: className forKey: @"$classname"];
      NSNumber *idx = [_classDefs objectForKey: className];
      [_objectsArray replaceObjectAtIndex: [idx unsignedIntegerValue] withObject: classDict];
    }

  // Fill NSIBObjectData at index 1
  NSMutableDictionary *od = [NSMutableDictionary dictionary];
  NSNumber *odClassIdx = [_classDefs objectForKey: @"NSIBObjectData"];
  [od setObject: makeCFSUID([odClassIdx unsignedIntegerValue]) forKey: @"$class"];

  NSUInteger ba = arrayStart;
  [od setObject: makeCFSUID(ba + 0) forKey: @"NSOidsKeys"];
  [od setObject: makeCFSUID(ba + 1) forKey: @"NSOidsValues"];
  [od setObject: makeCFSUID(ba + 2) forKey: @"NSObjectsKeys"];
  [od setObject: makeCFSUID(ba + 3) forKey: @"NSObjectsValues"];
  [od setObject: makeCFSUID(ba + 4) forKey: @"NSNamesKeys"];
  [od setObject: makeCFSUID(ba + 5) forKey: @"NSNamesValues"];
  [od setObject: makeCFSUID(ba + 6) forKey: @"NSConnections"];
  [od setObject: makeCFSUID(ba + 7) forKey: @"NSAccessibilityConnectors"];
  [od setObject: makeCFSUID(ba + 8) forKey: @"NSAccessibilityOidsKeys"];
  [od setObject: makeCFSUID(ba + 9) forKey: @"NSAccessibilityOidsValues"];
  [od setObject: makeCFSUID(ba + 10) forKey: @"NSClassesKeys"];
  [od setObject: makeCFSUID(ba + 11) forKey: @"NSClassesValues"];
  [od setObject: makeCFSUID(ba + 12) forKey: @"NSVisibleWindows"];
  [od setObject: makeCFSUID(frameworksIdx) forKey: @"NSFramework"];
  [od setObject: makeCFSUID(0) forKey: @"NSFontManager"];
  [od setObject: [NSNumber numberWithInt: maxOid + 1] forKey: @"NSNextOid"];
  [od setObject: makeCFSUID(arrayStart + 12) forKey: @"NSVisibleWindows"];

  {
      NSNumber *rootIndex = [_oidToIndex objectForKey: [NSNumber numberWithInt: rootOid]];
      if (rootIndex)
        [od setObject: makeCFSUID([rootIndex unsignedIntegerValue]) forKey: @"NSRoot"];
      else
        [od setObject: makeCFSUID(0) forKey: @"NSRoot"];
  }

  [_objectsArray replaceObjectAtIndex: 1 withObject: od];
  return YES;
}

- (BOOL) writeToNib: (NSString *)nibPath
{
  if (![self _parsePlist])
    return NO;

  if (![self _buildObjectsArray])
    return NO;

  NSMutableDictionary *root = [NSMutableDictionary dictionary];
  [root setObject: @"NSKeyedArchiver" forKey: @"$archiver"];
  [root setObject: _objectsArray forKey: @"$objects"];
  [root setObject: [NSNumber numberWithInt: 100000] forKey: @"$version"];

  NSDictionary *top = [NSDictionary dictionaryWithObject: makeCFSUID(1)
                                                  forKey: @"IB.objectdata"];
  [root setObject: top forKey: @"$top"];

  NSString *errorDesc = nil;
  NSData *xmlData = [NSPropertyListSerialization dataFromPropertyList: root
                                                               format: NSPropertyListXMLFormat_v1_0
                                                     errorDescription: &errorDesc];
  if (xmlData == nil)
    return NO;

  NSFileManager *fm = [NSFileManager defaultManager];
  BOOL isDir = NO;
  if ([fm fileExistsAtPath: nibPath isDirectory: &isDir])
    {
      if (!isDir)
        return NO;
    }
  else
    {
      if (![fm createDirectoryAtPath: nibPath
         withIntermediateDirectories: YES
                          attributes: nil
                               error: NULL])
        return NO;
    }

  NSString *keyedPath = [nibPath stringByAppendingPathComponent: @"keyedobjects.nib"];
  if (![xmlData writeToFile: keyedPath atomically: YES])
    return NO;

  // Write classes.nib
  NSDictionary *classesPlist = [NSDictionary dictionaryWithObject: [NSArray array]
                                                           forKey: @"IBClasses"];
  NSData *classesData = [NSPropertyListSerialization dataFromPropertyList: classesPlist
                                                                   format: NSPropertyListXMLFormat_v1_0
                                                         errorDescription: NULL];
  if (classesData == nil)
    return NO;

  NSString *classesPath = [nibPath stringByAppendingPathComponent: @"classes.nib"];
  if (![classesData writeToFile: classesPath atomically: YES])
    return NO;

  // Write info.nib
  NSDictionary *docInfo = [NSDictionary dictionaryWithObjectsAndKeys:
    @"com.apple.InterfaceBuilder3.Cocoa.XIB", @"type",
    @"3.0", @"version",
    nil];
  NSDictionary *infoPlist = [NSDictionary dictionaryWithObject: docInfo
                                                        forKey: @"IBDocumentInfo"];
  NSData *infoData = [NSPropertyListSerialization dataFromPropertyList: infoPlist
                                                                format: NSPropertyListXMLFormat_v1_0
                                                      errorDescription: NULL];
  if (infoData == nil)
    return NO;

  NSString *infoPath = [nibPath stringByAppendingPathComponent: @"info.nib"];
  if (![infoData writeToFile: infoPath atomically: YES])
    return NO;

  return YES;
}

@end
