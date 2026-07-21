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
          NSString *numStr = [str substringWithRange: NSMakeRange(prefixLen,
            [str length] - prefixLen - suffixLen)];
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
      NSString *numStr = [str substringWithRange: NSMakeRange(prefixLen,
        [str length] - prefixLen - suffixLen)];
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

  // Collect class names
  NSMutableSet *classNames = [NSMutableSet set];
  [classNames addObject: @"NSIBObjectData"];
  [classNames addObject: @"NSMutableArray"];
  [classNames addObject: @"NSNumber"];
  [classNames addObject: @"NSString"];
  for (NSDictionary *objDict in _sortedObjects)
    {
      NSString *clsName = [objDict objectForKey: @"isa"];
      if (clsName)
        [classNames addObject: clsName];
    }

  _objectsArray = [[NSMutableArray alloc] init];
  _classDefs = [[NSMutableDictionary alloc] init];

#define ADD_ENTRY(obj) ({ id _o = (obj); [_objectsArray addObject: _o]; [_objectsArray count] - 1; })

  // 0: $null
  [_objectsArray addObject: @"$null"];
  // 1: placeholder for NSIBObjectData
  [_objectsArray addObject: [NSNull null]];

  // Phase 1: user objects (placeholders) + build array data
  int maxOid = 0;
  NSMutableArray *oidsKeys = [NSMutableArray array];
  NSMutableArray *oidsValues = [NSMutableArray array];
  NSMutableArray *objectsKeys = [NSMutableArray array];
  NSMutableArray *objectsValues = [NSMutableArray array];
  NSMutableArray *namesKeys = [NSMutableArray array];
  NSMutableArray *namesValues = [NSMutableArray array];
  NSUInteger firstUserIdx = [_objectsArray count];

  for (NSDictionary *objDict in _sortedObjects)
    {
      int oidInt = [[objDict objectForKey: @"id"] intValue];
      if (oidInt > maxOid) maxOid = oidInt;

      // User object placeholder (keys filled in phase 2)
      NSMutableDictionary *entry = [NSMutableDictionary dictionary];
      NSUInteger objIdx = ADD_ENTRY(entry);
      [_oidToIndex setObject: [NSNumber numberWithUnsignedInteger: objIdx]
                      forKey: [NSNumber numberWithInt: oidInt]];

      NSDictionary *thisRef = makeCFSUID(objIdx);
      [oidsKeys addObject: thisRef];
      [oidsValues addObject: [NSNumber numberWithInt: oidInt]];  // placeholder, fix later
      [objectsKeys addObject: thisRef];
      [objectsValues addObject: thisRef];
      [namesKeys addObject: thisRef];
      [namesValues addObject: [objDict objectForKey: @"isa"] ?: @""];  // placeholder
    }

  // Phase 2: add value entries for oids and names
  NSMutableArray *oidsValRefs = [NSMutableArray array];
  NSMutableArray *namesValRefs = [NSMutableArray array];
  for (int i = 0; i < [_sortedObjects count]; i++)
    {
      int oidInt = [[[_sortedObjects objectAtIndex: i] objectForKey: @"id"] intValue];
      NSUInteger oidValIdx = ADD_ENTRY([NSNumber numberWithInt: oidInt]);
      [oidsValRefs addObject: makeCFSUID(oidValIdx)];

      NSString *nameStr = [[_sortedObjects objectAtIndex: i] objectForKey: @"isa"] ?: @"";
      NSUInteger nameValIdx = ADD_ENTRY(nameStr);
      [namesValRefs addObject: makeCFSUID(nameValIdx)];
    }
  // Replace placeholders in oidsValues and namesValues with real CF$UID refs
  [oidsValues removeAllObjects];
  [oidsValues addObjectsFromArray: oidsValRefs];
  [namesValues removeAllObjects];
  [namesValues addObjectsFromArray: namesValRefs];

  // Phase 3: fill user object keys
  NSUInteger ui = firstUserIdx;
  for (NSDictionary *objDict in _sortedObjects)
    {
      NSDictionary *keys = [objDict objectForKey: @"keys"];
      NSMutableDictionary *entry = [_objectsArray objectAtIndex: ui];
      [entry setObject: @"__tmp_class__" forKey: @"__tmp_class__"];
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
      ui++;
    }

  // Phase 3: support arrays (all CF$UID refs, no raw values)
  NSArray *arrData[] = { oidsKeys, oidsValues, objectsKeys, objectsValues,
                         namesKeys, namesValues };
  NSUInteger arrIndices[13];
  for (int i = 0; i < 6; i++)
    {
      NSMutableDictionary *aEntry = [NSMutableDictionary dictionary];
      [aEntry setObject: @"__tmp_class__" forKey: @"__tmp_class__"];
      if ([arrData[i] count] > 0)
        [aEntry setObject: arrData[i] forKey: @"NS.objects"];
      arrIndices[i] = ADD_ENTRY(aEntry);
    }
  // Empty arrays
  for (int i = 6; i < 13; i++)
    {
      NSMutableDictionary *aEntry = [NSMutableDictionary dictionary];
      [aEntry setObject: @"__tmp_class__" forKey: @"__tmp_class__"];
      arrIndices[i] = ADD_ENTRY(aEntry);
    }
  // Frameworks string
  NSUInteger frameworksIdx = ADD_ENTRY(@"IBCocoaFramework");

  // Phase 4: class definitions
  for (NSString *className in [classNames allObjects])
    {
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
          [hierarchy addObject: @"NSObject"];
        }
      NSMutableDictionary *classDict = [NSMutableDictionary dictionary];
      [classDict setObject: hierarchy forKey: @"$classes"];
      [classDict setObject: className forKey: @"$classname"];
      NSUInteger clsIdx = ADD_ENTRY(classDict);
      [_classDefs setObject: [NSNumber numberWithUnsignedInteger: clsIdx] forKey: className];
    }

  // Fix user object $class refs
  ui = firstUserIdx;
  for (NSDictionary *objDict in _sortedObjects)
    {
      NSString *clsName = [objDict objectForKey: @"isa"];
      NSMutableDictionary *entry = [_objectsArray objectAtIndex: ui];
      [entry removeObjectForKey: @"__tmp_class__"];
      NSNumber *classIdx = [_classDefs objectForKey: clsName];
      [entry setObject: makeCFSUID([classIdx unsignedIntegerValue]) forKey: @"$class"];
      ui++;
    }

  // Fix array $class refs
  NSNumber *arrClassIdx = [_classDefs objectForKey: @"NSMutableArray"];
  for (int i = 0; i < 13; i++)
    {
      NSMutableDictionary *entry = [_objectsArray objectAtIndex: arrIndices[i]];
      [entry removeObjectForKey: @"__tmp_class__"];
      [entry setObject: makeCFSUID([arrClassIdx unsignedIntegerValue]) forKey: @"$class"];
    }

  // Phase 5: NSIBObjectData at index 1
  NSMutableDictionary *od = [NSMutableDictionary dictionary];
  NSNumber *odClassIdx = [_classDefs objectForKey: @"NSIBObjectData"];
  [od setObject: makeCFSUID([odClassIdx unsignedIntegerValue]) forKey: @"$class"];

  [od setObject: makeCFSUID(arrIndices[0]) forKey: @"NSOidsKeys"];
  [od setObject: makeCFSUID(arrIndices[1]) forKey: @"NSOidsValues"];
  [od setObject: makeCFSUID(arrIndices[2]) forKey: @"NSObjectsKeys"];
  [od setObject: makeCFSUID(arrIndices[3]) forKey: @"NSObjectsValues"];
  [od setObject: makeCFSUID(arrIndices[4]) forKey: @"NSNamesKeys"];
  [od setObject: makeCFSUID(arrIndices[5]) forKey: @"NSNamesValues"];
  [od setObject: makeCFSUID(arrIndices[6]) forKey: @"NSConnections"];
  [od setObject: makeCFSUID(arrIndices[7]) forKey: @"NSAccessibilityConnectors"];
  [od setObject: makeCFSUID(arrIndices[8]) forKey: @"NSAccessibilityOidsKeys"];
  [od setObject: makeCFSUID(arrIndices[9]) forKey: @"NSAccessibilityOidsValues"];
  [od setObject: makeCFSUID(arrIndices[10]) forKey: @"NSClassesKeys"];
  [od setObject: makeCFSUID(arrIndices[11]) forKey: @"NSClassesValues"];
  [od setObject: makeCFSUID(arrIndices[12]) forKey: @"NSVisibleWindows"];
  [od setObject: makeCFSUID(frameworksIdx) forKey: @"NSFramework"];
  [od setObject: makeCFSUID(0) forKey: @"NSFontManager"];
  [od setObject: [NSNumber numberWithInt: maxOid + 1] forKey: @"NSNextOid"];

  NSNumber *rootIndex = [_oidToIndex objectForKey: [NSNumber numberWithInt: rootOid]];
  if (rootIndex)
    [od setObject: makeCFSUID([rootIndex unsignedIntegerValue]) forKey: @"NSRoot"];
  else
    [od setObject: makeCFSUID(0) forKey: @"NSRoot"];

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
