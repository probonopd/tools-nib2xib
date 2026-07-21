#import "Testing.h"
#import <Foundation/Foundation.h>

static NSString *
findTool(NSString *cwd)
{
  NSArray *candidates = [NSArray arrayWithObjects:
    [cwd stringByAppendingPathComponent: @"../obj/nib2xib"],
    [cwd stringByAppendingPathComponent: @"../../obj/nib2xib"],
    nil];
  NSEnumerator *en = [candidates objectEnumerator];
  NSString *path;
  while ((path = [en nextObject]) != nil)
    {
      if ([[NSFileManager defaultManager] isExecutableFileAtPath: path])
        return path;
    }
  return nil;
}

static BOOL
runTool(NSString *toolPath, NSString *input, NSString *output)
{
  NSTask *task = [[NSTask alloc] init];
  [task setLaunchPath: toolPath];
  [task setArguments: [NSArray arrayWithObjects: input, output, nil]];
  [task launch];
  [task waitUntilExit];
  BOOL ok = ([task terminationStatus] == 0);
  [task release];
  return ok;
}

int
main()
{
  CREATE_AUTORELEASE_POOL(arp);

  NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
  if ([[cwd lastPathComponent] isEqualToString: @"obj"])
    {
      cwd = [cwd stringByDeletingLastPathComponent];
    }

  NSString *toolPath = findTool(cwd);
  PASS(toolPath != nil, "Found nib2xib binary");
  if (toolPath == nil)
    {
      DESTROY(arp);
      return 1;
    }

  NSString *dpNib = [cwd stringByAppendingPathComponent: @"DesktopPref.nib"];
  NSString *tnNib = [cwd stringByAppendingPathComponent: @"Test-nib.nib"];

  NSString *dpXib = @"/tmp/nib2xib_dp.xib";
  NSString *dpXib2 = @"/tmp/nib2xib_dp_2.xib";
  NSString *tnXib = @"/tmp/nib2xib_tn.xib";
  NSString *dpPlist = @"/tmp/nib2xib_dp.uiplist";
  NSString *dpPlist2 = @"/tmp/nib2xib_dp_2.uiplist";
  NSString *tnPlist = @"/tmp/nib2xib_tn.uiplist";

  START_SET("nib2xib XIB conversion")

    BOOL dpExists = [[NSFileManager defaultManager] fileExistsAtPath: dpNib];
    PASS(dpExists, "DesktopPref.nib fixture exists");
    if (!dpExists) { SKIP("Missing DesktopPref.nib fixture"); }

    PASS(runTool(toolPath, dpNib, dpXib), "DesktopPref.nib -> .xib succeeds");

    NSString *xib = [NSString stringWithContentsOfFile: dpXib];
    PASS(xib != nil, "XIB output is readable");
    PASS([xib hasPrefix: @"<?xml"], "XIB starts with <?xml>");
    PASS([xib rangeOfString: @"<document"].location != NSNotFound,
      "XIB has document element");

    BOOL tnExists = [[NSFileManager defaultManager] fileExistsAtPath: tnNib];
    PASS(tnExists, "Test-nib.nib fixture exists");
    if (!tnExists) { SKIP("Missing Test-nib.nib fixture"); }

    PASS(runTool(toolPath, tnNib, tnXib), "Test-nib.nib -> .xib succeeds");

    NSString *tnXibContent = [NSString stringWithContentsOfFile: tnXib];
    PASS(tnXibContent != nil, "Test-nib XIB output is readable");
    PASS([tnXibContent hasPrefix: @"<?xml"], "Test-nib XIB starts with <?xml>");

  END_SET("nib2xib XIB conversion")

  START_SET("nib2xib UIPlist conversion")

    PASS(runTool(toolPath, dpNib, dpPlist), "DesktopPref.nib -> .uiplist succeeds");

    NSString *plist = [NSString stringWithContentsOfFile: dpPlist];
    PASS(plist != nil, "UIPlist output is readable");
    PASS([plist rangeOfString: @"objects ="].location != NSNotFound,
      "UIPlist has objects array");
    PASS([plist rangeOfString: @"id ="].location != NSNotFound,
      "UIPlist has id fields");
    PASS([plist rangeOfString: @"isa ="].location != NSNotFound,
      "UIPlist has isa fields");
    PASS([plist rangeOfString: @"@"].location != NSNotFound,
      "UIPlist has @oid references");

    PASS([plist rangeOfString: @"0x"].location == NSNotFound,
      "UIPlist has no hex addresses");

    PASS(runTool(toolPath, tnNib, tnPlist), "Test-nib.nib -> .uiplist succeeds");
    NSString *tnPlistContent = [NSString stringWithContentsOfFile: tnPlist];
    PASS(tnPlistContent != nil, "Test-nib UIPlist output is readable");
    PASS([tnPlistContent rangeOfString: @"objects ="].location != NSNotFound,
      "Test-nib UIPlist has objects array");

  END_SET("nib2xib UIPlist conversion")

  START_SET("nib2xib determinism")

    PASS(runTool(toolPath, dpNib, dpXib2), "Second XIB conversion succeeds");
    NSString *xib = [NSString stringWithContentsOfFile: dpXib];
    NSString *xib2 = [NSString stringWithContentsOfFile: dpXib2];
    BOOL xibSame = [xib isEqualToString: xib2];
    PASS(xibSame, "XIB output is deterministic");
    if (!xibSame)
      {
        fprintf(stderr, "(XIB non-determinism may be due to ASLR - oids use [obj hash])\n");
      }

    PASS(runTool(toolPath, dpNib, dpPlist2), "Second UIPlist conversion succeeds");
    NSString *plistFile1 = [NSString stringWithContentsOfFile: dpPlist];
    NSString *plistFile2 = [NSString stringWithContentsOfFile: dpPlist2];
    PASS([plistFile1 isEqualToString: plistFile2],
      "UIPlist output is deterministic");

  END_SET("nib2xib determinism")

  START_SET("nib2xib structure validation")

    NSString *plist = [NSString stringWithContentsOfFile: dpPlist];

    // Count id and isa using line-anchored regex
    // Avoiding false positives like 'coordinates_valid = 1;' matching 'id = 1;'
    NSRegularExpression *idRegex = [NSRegularExpression
      regularExpressionWithPattern: @"^\\s*id = \\d+;$"
      options: NSRegularExpressionAnchorsMatchLines error: NULL];
    NSRegularExpression *isaRegex = [NSRegularExpression
      regularExpressionWithPattern: @"^\\s*isa = \\w+;$"
      options: NSRegularExpressionAnchorsMatchLines error: NULL];
    NSUInteger idCount = [idRegex numberOfMatchesInString: plist
      options: 0 range: NSMakeRange(0, [plist length])];
    NSUInteger isaCount = [isaRegex numberOfMatchesInString: plist
      options: 0 range: NSMakeRange(0, [plist length])];

    PASS(idCount > 0, "UIPlist contains %lu id statements", (unsigned long)idCount);
    PASS(isaCount > 0, "UIPlist contains %lu isa statements", (unsigned long)isaCount);
    PASS(idCount == isaCount, "UIPlist has same number of id and isa (%lu vs %lu)",
      (unsigned long)idCount, (unsigned long)isaCount);

    NSString *xib = [NSString stringWithContentsOfFile: dpXib];
    PASS([xib rangeOfString: @"<objects>"].location != NSNotFound,
      "XIB has objects section");
    PASS([xib rangeOfString: @"</objects>"].location != NSNotFound,
      "XIB closes objects section");
    PASS([xib rangeOfString: @"<dependencies>"].location != NSNotFound,
      "XIB has dependencies section");

  END_SET("nib2xib structure validation")

  DESTROY(arp);
  return 0;
}
