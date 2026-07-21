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
#import <Foundation/Foundation.h>
#import <sys/resource.h>

#import "NIBParser.h"
#import "UIPlistWriter.h"
#import "UIPlistReader.h"

static void
usage(void)
{
  puts("Usage: uiconvert input output");
  puts("");
  puts("  File extensions determine the conversion direction:");
  puts("  .nib   \342\206\222 .xib       Interface Builder XML (loadable by GNUstep)");
  puts("  .nib   \342\206\222 .uiplist   git-friendly object graph dump");
  puts("  .uiplist \342\206\222 .nib     restore .nib bundle from .uiplist");
}

int main(int argc, const char *argv[]) 
{
  struct rlimit rl = { RLIM_INFINITY, RLIM_INFINITY };
  setrlimit(RLIMIT_STACK, &rl);

  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  [NSApplication sharedApplication];

  if (argc != 3)
    {
      usage();
      [pool release];
      return 1;
    }

  NSString *inputPath = [NSString stringWithCString: argv[1]];
  NSString *outputPath = [NSString stringWithCString: argv[2]];
  NSString *inputExt = [[inputPath pathExtension] lowercaseString];
  NSString *outputExt = [[outputPath pathExtension] lowercaseString];

  // .uiplist → .nib
  if ([inputExt isEqualToString: @"uiplist"]
    && [outputExt isEqualToString: @"nib"])
    {
      UIPlistReader *reader = [[UIPlistReader alloc] initWithContentsOfFile: inputPath];
      if (reader == nil)
        {
          NSLog(@"Failed to initialize UIPlistReader");
          [pool release];
          return 1;
        }
      BOOL ok = [reader writeToNib: outputPath];
      [reader release];
      if (!ok)
        {
          NSLog(@"Failed to write %@", outputPath);
          [pool release];
          return 1;
        }
      [pool release];
      return 0;
    }

  // .nib → anything (xib or uiplist)
  if ([inputExt isEqualToString: @"nib"])
    {
      NIBParser *parser = [[NIBParser alloc] initWithNibNamed: inputPath];
      if (parser == nil)
        {
          NSLog(@"Parser initialization failed");
          [pool release];
          return 1;
        }
      id output = [parser parse];
      if (output == nil)
        {
          NSLog(@"Parse returned nil");
          [pool release];
          return 1;
        }
      NSString *outputStr = nil;

      if ([outputExt isEqualToString: @"uiplist"])
        {
          id objectData = [parser objectData];
          if (objectData == nil)
            {
              NSLog(@"No object data available for UIPlist output");
              [pool release];
              return 1;
            }
          UIPlistWriter *writer;
          writer = [[UIPlistWriter alloc] initWithObjectData: objectData];
          outputStr = [writer string];
          [writer release];
        }
      else
        {
          outputStr = [output description];
        }

      BOOL f = [outputStr writeToFile: outputPath atomically: YES];
      [parser release];
      if (!f)
        {
          NSLog(@"Could not write file %@", outputPath);
          [pool release];
          return 1;
        }
      [pool release];
      return 0;
    }

  // Unsupported direction
  usage();
  [pool release];
  return 1;
}
