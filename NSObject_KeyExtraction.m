/*
   Copyright (C) 2024 Free Software Foundation, Inc.

   Written by: Gregory John Casamento <greg.casamento@gmail.com>
   Date: 2024

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02110 USA.
*/

#import <objc/runtime.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#import "NSObject_KeyExtraction.h"
#import "NSString_Additions.h"
#import "XMLNode.h"
#import "OidProvider.h"

// #define DEBUG

@class NSInlineCString;

@implementation NSObject (KeyExtraction)

+ (void) getAllMethodsForClass: (Class)cls
		     intoArray: (NSMutableArray *)methodsArray
{
  if (cls == nil || cls == [NSObject class])
  {
    return;
  }

  unsigned int count = 0;
  Method *methods = class_copyMethodList(cls, &count);

  if (methods != NULL)
  {
    for (unsigned int i = 0; i < count; i++)
    {
      SEL method_name = method_getName(methods[i]);
      NSString *methodName = NSStringFromSelector(method_name);
      [methodsArray addObject: methodName];
    }
    free(methods);
  }

  // Recursively call this method for the superclass
  [self getAllMethodsForClass: class_getSuperclass(cls) intoArray: methodsArray];
}

+ (NSArray *) recursiveGetAllMethodsForClass: (Class)cls
{
  NSMutableArray *methodsArray = [NSMutableArray array];
  [self getAllMethodsForClass: cls
		    intoArray: methodsArray];
  return [methodsArray copy];
}

+ (NSArray *) skippedClasses
{
  NSArray *_skippedClasses = [NSArray arrayWithObjects: 
    @"NSDynamicSystemColor",
    @"NSNamedColorSpace",
    @"NSAttributedString",
    @"NSConcreteAttributedString",
    @"NSFont",
    @"NSImage",
    @"NSColor",
    @"NSCachedWhiteColor",
    @"NSCachedBlackColor",
    nil];  
  return _skippedClasses;
}

+ (NSArray *) skippedKeys
{
  NSArray *_skippedKeys = [NSArray arrayWithObjects: 
    @"needsDisplay",
    @"needsDisplayInRect",
    @"upGState",
    @"allowsEditingTextAttributes", 
    @"importsGraphics", 
    @"delegate", 
    @"errorAction", 
    @"postsBoundsChangedNotifications", 
    @"postsFrameChangedNotifications", 
    @"nextKeyView",
    @"prevKeyView",
    @"nextResponder",
    @"boundsOrigin", // not defined on some objects...
    @"frameOrigin", // not defined on some objects...
    @"floatValue", 
    @"doubleValue",
    @"intValue",
    @"objectValue", // usually the same as stringValue
    @"mnemonicLocation", // mnemonics are no longer used...
    @"state",
    // @"font",
    @"textColor",
    @"backgroundColor",
    @"keyEquivalentFont",
    @"alternateObjectValue",
    @"action",
    @"target",
    @"keyEquivalent",
    @"keyEquivalentModifierMask",
    @"autoenablesItems",
    @"selectedCell",
    @"selectedCellTag",
    @"selectedCellIndex",
    @"selectedCellIndexPath",
    @"selectedCellTagPath",
    @"selectedItem",
    @"titleWithMnemonic",
    @"titleWithMnemonic:withFont:",
    @"titleWithMnemonic:withFont:withAttributes:",
    @"titleWithMnemonic:withFont:withAttributes:withColor:",
    @"titleWithMnemonic:withFont:withAttributes:withColor:withSize:",
    @"titleWithMnemonic:withFont:withAttributes:withColor:withSize:withStyle:",
    @"titleWithMnemonic:withFont:withAttributes:withColor:withSize:withStyle:withAlignment:",
    @"titleWithMnemonic:withFont:withAttributes:withColor:withSize:withStyle:withAlignment:withLineBreakMode:",
    @"titleOfSelectedItem",
    @"titleOfSelectedItemWithMnemonic",
    @"pullsDown",
    @"contentSize",
    @"sound",
    @"alternateImage",
    nil];
  return _skippedKeys;
}

+ (NSArray *) keyObjects
{
  NSArray *_keyObjects = [NSArray arrayWithObjects:
    @"contentView",
    @"cell",
    @"contentRect",
    @"screenRect",
    @"frame",
    @"autoresizingMask",
    @"windowStyleMask",
    @"bounds",
    @"font",
    nil];
  return _keyObjects;
}

+ (NSArray *) nonObjects
{
  NSArray *_nonObjects = [NSArray arrayWithObjects:
    @"contentRect",
    @"screenRect",
    @"frame",
    @"autoresizingMask",
    @"windowStyleMask",
    @"windowPositionMask",
    @"interfaceStyle", 
    @"boundsRotation", 
    @"boundsSize", 
    @"bounds",
    @"frameRotation", 
    @"frame", 
    @"frameSize", 
    @"autoresizesSubviews",
    @"minSize",
    @"drawsBackground",
    @"alignment", 
    @"tag", 
    @"type",
    @"wraps",
    @"imageDimsWhenDisabled",
    @"highlightsBy",
    @"showsStateBy",
    @"refusesFirstResponder",
    @"isBezeled", 
    @"isEnabled",
    @"isScrollable",
    @"isSelectable",
    @"isEditable",
    @"isBordered",
    @"imagePosition",
    @"imageScaling",
    @"imageAlignment",
    @"imageFrame",
    @"matchesOnMultipleResolution",
    @"prefersColorMatch",
    @"size",
    @"isContinuous",
    @"knobThickness",
    @"knobProportion",
    @"knobStyle",
    @"knobTrackingMode",
    @"knobTrackingMode",
    @"smartInsertDeleteEnabled",
    @"containerSize",
    @"containerOrigin",
    @"containerFrame",
    @"containerBounds",
    @"containerRect",
    @"containerFrameRotation",
    @"containerBoundsRotation",
    @"containerFrameSize",
    @"containerBoundsSize",
    @"containerFrameOrigin",
    @"containerBoundsOrigin",
    @"containerContentSize",
    @"containerContentOrigin",
    @"containerContentFrame",
    @"containerContentBounds",
    @"containerContentRect",
    @"widthTracksTextView",
    @"heightTracksTextView",
    @"textViewWidthTracksTextView",
    @"textViewHeightTracksTextView",
    @"textViewContentSize",
    @"textViewContentOrigin",
    @"textViewContentFrame",
    @"textViewContentBounds",
    @"textViewContentRect",
    @"textViewContainerSize",
    @"textViewContainerOrigin",
    @"textViewContainerFrame",
    @"textViewContainerBounds",
    @"textViewContainerRect",
    @"textViewContainerFrameRotation",
    @"textViewContainerBoundsRotation",
    @"textViewContainerFrameSize",
    @"textViewContainerBoundsSize",
    @"textViewContainerFrameOrigin",
    @"textViewContainerBoundsOrigin",
    @"textViewContainerContentSize",
    @"textViewContainerContentOrigin",
    @"textViewContainerContentFrame",
    @"textViewContainerContentBounds",
    @"textViewContainerContentRect",
    @"textViewContainerContentFrameRotation",
    @"textViewContainerContentBoundsRotation",
    @"textViewContainerContentFrameSize",
    @"textViewContainerContentBoundsSize",
    @"textViewContainerContentFrameOrigin",
    @"textViewContainerContentBoundsOrigin",
    @"textViewContainerContentRectRotation",
    @"textViewContainerContentRectSize",
    @"textViewContainerContentRectOrigin",
    @"textViewContainerContentRect",
    @"textViewContainerContentRectRotation",
    @"textViewContainerContentRectSize",
    @"textViewContainerContentRectOrigin",
    @"textViewContainerContentRect",
    @"usesScreenFonts",
    @"backgroundLayoutEnabled",
    @"maxSize",
    @"minSize",
    @"contentSize",
    @"contentOrigin",
    @"contentFrame",
    @"contentBounds",
    @"contentRect",
    @"cornerRadius",
    @"borderWidth",
    @"borderType",
    @"boxType",
    @"transparent",
    @"titlePosition",
    @"controlSize",
    @"controlTint",
    @"tabViewType",
    @"bezelStyle",
    @"buttonType",
    @"segmentedControlStyle",
    @"usesFontPanel",
    @"usesFindPanel",
    @"usesRuler",
    @"usesInspectorBar",
    @"usesInspectorBarForText",
    @"usesInspectorBarForTextView",
    @"intefaceStyle",
    @"menuChangedMessagesEnabled",
    @"alphaValue",
    @"hidden",
    @"isReleasedWhenClosed",
    @"isFlipped",
    @"isOpaque",
    @"isMovable",
    @"isMovableByWindowBackground",
    @"isVisible",
    @"isHidden",
    @"isMiniaturizable",
    @"isMiniaturized",
    @"isResizable",
    @"isZoomable",
    @"isZoomed",
    @"isFullScreen",
    @"isFullScreenCapable",
    @"isRestorable",
    @"isRestorationEnabled",
    @"isRestorationDisabled",
    @"isRestorationDisabledForWindow",
    @"isRestorationDisabledForView",
    @"isRestorationDisabledForViewController",
    @"isRestorationDisabledForController",
    @"aspectRatio",
    @"aspectRatioEnabled",
    @"aspectRatioDisabled",
    @"aspectRatioDisabledForWindow",
    @"aspectRatioDisabledForView",
    @"aspectRatioDisabledForViewController",
    @"aspectRatioDisabledForController",
    @"contentSize",
    @"contentOrigin",
    @"contentFrame",
    @"contentBounds",
    @"contentRect",
    @"contentRectRotation",
    @"contentRectSize",
    @"contentRectOrigin",
    @"drawsBackground",
    @"isOpaque",
    @"isFlipped",
    @"isMovable",
    @"isMovableByWindowBackground",
    @"isVisible",
    @"isHidden",
    @"isMiniaturizable",
    @"isMiniaturized",
    @"isResizable",
    @"isZoomable",
    @"isZoomed",
    @"isFullScreen",
    @"isFullScreenCapable",
    @"isRestorable",
    @"isRestorationEnabled",
    nil];
  return _nonObjects;
}

+ (NSDictionary *) keyMappings
{
  NSMutableDictionary *_keyMappings = [NSMutableDictionary dictionary];
  [_keyMappings setObject: [NSDictionary dictionaryWithObjectsAndKeys: @"title", @"stringValue", nil] 
                   forKey: @"NSTextFieldCell"];
  return _keyMappings;
}

- (NSSet *) keysForObject
{
  NSArray *methods = [NSObject recursiveGetAllMethodsForClass: [self class]];
  NSEnumerator *en = [methods objectEnumerator];
  NSString *selectorName = nil;
  NSMutableSet *result = [NSMutableSet setWithCapacity: [methods count]];
  NSSet *nonObjects = [NSSet setWithArray: [NSObject nonObjects]];
  NSSet *keyObjects = [NSSet setWithArray: [NSObject keyObjects]];
  
  while ((selectorName = [en nextObject]) != nil)
  {
    if ([selectorName hasPrefix: @"set"] && [selectorName isEqualToString: @"settings"] == NO)
		{
	  	NSString *keyName = [selectorName substringFromIndex: 3];
      SEL s = NULL;
      NSString *lowerKeyName = nil;

      if ([keyName length] == 0 || [keyName characterAtIndex: 0] == '_')
      {
        continue;
      }

      // remove the trailing colon if it exists
		  keyName = [keyName stringByReplacingOccurrencesOfString: @":" withString: @""];
		  lowerKeyName = [keyName lowercaseFirstCharacter];
      
      // if the object responds, add it... this way we know it's a key.
      s = NSSelectorFromString(lowerKeyName);
      if (s != NULL && [self respondsToSelector: s])
      {
        // Skip keys that return non-object types not in nonObjects
        NSMethodSignature *sig = [self methodSignatureForSelector: s];
        if (sig != nil)
        {
          const char *returnType = [sig methodReturnType];
          if (returnType != NULL && returnType[0] == '@')
          {
            [result addObject: lowerKeyName];
          }
          else if ([nonObjects containsObject: lowerKeyName]
                || [keyObjects containsObject: lowerKeyName])
          {
            [result addObject: lowerKeyName];
          }
        }
      }
      else
      {
        NSString *isKeyName = [NSString stringWithFormat: @"is%@", keyName];
        s = NSSelectorFromString(isKeyName);

        if(s != NULL && [self respondsToSelector: s])
        {
          // Include is* keys only if they return BOOL
          NSMethodSignature *sig = [self methodSignatureForSelector: s];
          if (sig != nil)
          {
            const char *returnType = [sig methodReturnType];
            if (returnType != NULL && returnType[0] == 'c')
            {
              [result addObject: isKeyName];
            }
          }
        }
      }
		}
  } 

  return result;
}

- (NSString *) classNameForParser
{
  NSString *className = NSStringFromClass([self class]);    
  return className;
}

- (XMLNode *) processObjectWithParser: (id<OidProvider>)parser
{
  NSString *className = [self classNameForParser];    

  if ([[NSObject skippedClasses] containsObject: className])
  {
    return nil;
  }

  if ([parser isObjectProcessed: self])
  {
    return [parser processedObject: self];
  }

  NSString *name = [className classNameToTagName];
  XMLNode *result = [[XMLNode alloc] initWithName: name];
  NSString *oid = [parser oidForObject: self];

  [parser addProcessedObject: self withNode: result];

  NSSet *allKeys = [self keysForObject];
  NSEnumerator *e = [allKeys objectEnumerator];
  id k = nil;

#ifdef DEBUG
  if ([self isKindOfClass: [NSView class]])
  {
    NSLog(@"class = %@, keys = %@", className, allKeys);
  }
#endif

  [result addAttribute: @"id" value: oid];
  while ( (k = [e nextObject]) != nil )
  { 
    if ([[NSObject skippedKeys] containsObject: k] == NO)
    {
      SEL s = NSSelectorFromString(k);
      NSMethodSignature *signature = [NSMethodSignature methodSignatureForSelector: s];
      IMP imp = NULL;

      // If the selector is NULL, skip it...
      if (s == NULL && signature != nil)
      {
        NSLog(@"ERROR getting the selector/signature %@", k);
        break;
      }
      else
      {
        imp = [self methodForSelector: s];
      }

      if ([[NSObject nonObjects] containsObject: k]) // frames, sizes, flags...
      {
        const char *returnType = [signature methodReturnType];
        XMLNode *node = nil;

        // rect/frame, etc... non objects
        if ([k hasSuffix: @"Rect"] || [k isEqualToString: @"frame"] || [k isEqualToString: @"bounds"])
        {
          if (returnType != NULL && returnType[0] == '{')
          {
            NSRect (*func)(id, SEL) = (NSRect (*)(id, SEL))imp;
            NSRect rect = (func)(self, s);
            node = [XMLNode nodeForRect: rect type: k];
          }
        }
        else if ([k hasSuffix: @"Size"])
        {
          if (returnType != NULL && returnType[0] == '{')
          {
            NSSize (*func)(id, SEL) = (NSSize (*)(id, SEL))imp;
            NSSize size = (func)(self, s);
            node = [XMLNode nodeForSize: size type: k];
          }
        }
        else if ([k hasSuffix: @"Mask"])
        {
          if ([k isEqualToString: @"autoresizingMask"])
          {
            unsigned int mask = [(NSView *)self autoresizingMask];
            node = [[XMLNode alloc] initWithName: k];
            [node addAttribute: @"key" value: k];
            if (mask & NSViewMaxXMargin)
            {
              [node addAttribute: @"flexibleMaxX" value: @"YES"];
            }
            if (mask & NSViewMaxYMargin)
            {
              [node addAttribute: @"flexibleMaxY" value: @"YES"];        
            }
            if (mask & NSViewMinXMargin)
            {
              [node addAttribute: @"flexibleMinY" value: @"YES"];           
            }
            if (mask & NSViewMinYMargin)
            {
              [node addAttribute: @"flexibleMinY" value: @"YES"]; 
            }
          }
        }
        else if ([k hasPrefix: @"is"])
        {
          if (returnType != NULL && returnType[0] == 'c')
          {
            BOOL (*func)(id, SEL) = (BOOL (*)(id, SEL))imp;
            BOOL f = (func)(self, s);

            if ([k isEqualToString: @"isBezeled"])
            {
              if (f == YES)
              {
                if ([self isKindOfClass: [NSTextFieldCell class]])
                {
                  [result addAttribute: @"borderStyle" value: @"bezel"];
                }
                else
                {
                  [result addAttribute: @"type" value: @"bevel"];
                }
              }
            }
            else if ([k isEqualToString: @"isBordered"])
            {
              if (f == YES)
              {
                [result addAttribute: @"borderStyle" value: @"border"];
              }
            }
            else
            {
              NSString *name = [k stringByReplacingOccurrencesOfString: @"is" withString: @""];
              name = [name lowercaseFirstCharacter];
              if (f == YES)
              {
                [result addAttribute: name value: @"YES"];
              }
            }
          }
        }

        if (node != nil)
        {
          [result addElement: node];
        }
      }
      else // Objects...
      {
        id o = [self performSelector: s];
        
        if (o == nil)
        {
          continue;
        }

        if ([[NSObject keyObjects] containsObject: k])
        {
          XMLNode *node = [o processObjectWithParser: parser];

          if(node != nil)
          {
            if ([o isKindOfClass: [NSCell class]])
            {
              [node addAttribute: @"key" value: @"cell"];
            }

            [result addElement: node];
            // [parser addConnectionsForObject: o toNode: node];
          }
        }
        else
        {
#ifdef DEBUG        
          NSLog(@"Current object = %@", k);
#endif
          if ([o isKindOfClass: [NSArray class]])
          {
            NSEnumerator *aen = [o objectEnumerator];
            id obj = nil;
            XMLNode *arrayObject = [[XMLNode alloc] initWithName: k];

            while ((obj = [aen nextObject]) != nil)
            {
              XMLNode *xmlObject = [obj processObjectWithParser: parser];
              if (xmlObject != nil)
              {
                [arrayObject addElement: xmlObject];
                [parser addConnectionsForObject: obj toNode: xmlObject];
              }
            }

            // if count is greater than 0, then add the array, otherwise...
            if ([o count] > 0)
            {
              [result addElement: arrayObject];
            }
          }
          else if ([o isKindOfClass: [NSString class]] 
		   && [o isKindOfClass: [NSAttributedString class]] == NO)
          {
            NSString *filteredString = [o stringByReplacingOccurrencesOfString: @"\n" withString: @""];
            NSDictionary *dict = [[NSObject keyMappings] objectForKey: className];

            if (dict != nil)
            {
              NSString *mappedKey = [dict objectForKey: k];
              if (mappedKey != nil)
              {
                k = mappedKey;
              }
            }
            [result addAttribute: k value: filteredString];
            // [parser addConnectionsForObject: o toNode: result];
          }
          else if ([o isKindOfClass: [NSString class]] == NO) // don't parse into these types...
          {
            XMLNode *node = [o processObjectWithParser: parser];
            if (node != nil)
            {
              [result addElement: node];
              [parser addConnectionsForObject: o toNode: node];
            }
          }
        }
      }
    }
  }

  return result;
}

@end