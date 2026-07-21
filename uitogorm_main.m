/* Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This file is part of GNUstep.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

#import "UIPlistReader.h"

int main(int argc, const char *argv[])
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  [NSApplication sharedApplication];

  if (argc != 3)
    {
      printf("Usage: uitogorm input.uiplist output.gorm\n");
      [pool release];
      return 1;
    }

  NSString *inputPath = [NSString stringWithCString: argv[1]];
  NSString *outputPath = [NSString stringWithCString: argv[2]];

  // Use UIPlistReader to convert to .nib (NSKeyedArchiver XML)
  UIPlistReader *reader = [[UIPlistReader alloc] initWithContentsOfFile: inputPath];
  if (reader == nil)
    {
      NSLog(@"Failed to read %@", inputPath);
      [pool release];
      return 1;
    }

  if (![reader writeToNib: outputPath])
    {
      NSLog(@"Failed to write .nib format to %@", outputPath);
      [reader release];
      [pool release];
      return 1;
    }
  [reader release];

  // UIPlistReader.writeToNib: creates a .nib bundle with keyedobjects.nib.
  // We need a .gorm bundle with the same content.
  // The .nib bundle already IS the right format - just rename?
  // No, writeToNib: creates the .nib directory structure.
  // We created outputPath as .gorm but the content is .nib format.
  // That's fine - the .gorm bundle has the same structure as .nib.

  // Rename the written keyedobjects.nib to objects.gorm so Gorm can find it
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *keyedPath = [outputPath stringByAppendingPathComponent: @"keyedobjects.nib"];
  NSString *gormDataPath = [outputPath stringByAppendingPathComponent: @"objects.gorm"];
  if ([fm fileExistsAtPath: keyedPath])
    {
      [fm moveItemAtPath: keyedPath toPath: gormDataPath error: NULL];
    }

  // Also write a flag file to indicate this is a keyed-archive .gorm
  NSString *flagPath = [outputPath stringByAppendingPathComponent: @"data.keyed"];
  [@"1" writeToFile: flagPath atomically: YES encoding: NSUTF8StringEncoding error: NULL];

  printf("Wrote %s (NSKeyedArchiver format)\n", [outputPath UTF8String]);
  [pool release];
  return 0;
}
