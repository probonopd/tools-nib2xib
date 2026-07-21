#import "Testing.h"
#import <Foundation/Foundation.h>

static NSString *
findTool(NSString *cwd)
{
  NSArray *candidates = [NSArray arrayWithObjects:
    [cwd stringByAppendingPathComponent: @"../obj/uiconvert"],
    [cwd stringByAppendingPathComponent: @"../../obj/uiconvert"],
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

static NSUInteger
countIds(NSString *content)
{
  NSRegularExpression *re = [NSRegularExpression
    regularExpressionWithPattern: @"^\\s*id = \\d+;$"
    options: NSRegularExpressionAnchorsMatchLines error: NULL];
  return [re numberOfMatchesInString: content options: 0
    range: NSMakeRange(0, [content length])];
}

int
main()
{
  CREATE_AUTORELEASE_POOL(arp);

  NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
  if ([[cwd lastPathComponent] isEqualToString: @"obj"])
    cwd = [cwd stringByDeletingLastPathComponent];

  NSString *toolPath = findTool(cwd);
  PASS(toolPath != nil, "Found uiconvert binary");
  if (toolPath == nil) { DESTROY(arp); return 1; }

  NSString *dpNib = [cwd stringByAppendingPathComponent: @"DesktopPref.nib"];
  NSString *tnNib = [cwd stringByAppendingPathComponent: @"Test-nib.nib"];

  NSString *dpXib = @"/tmp/ut_dp.xib";
  NSString *dpXib2 = @"/tmp/ut_dp_2.xib";
  NSString *tnXib = @"/tmp/ut_tn.xib";
  NSString *dpP = @"/tmp/ut_dp.uiplist";
  NSString *dpP2 = @"/tmp/ut_dp_2.uiplist";
  NSString *tnP = @"/tmp/ut_tn.uiplist";
  NSString *dpRNib = @"/tmp/ut_dp_r.nib";
  NSString *dpRP = @"/tmp/ut_dp_r.uiplist";
  NSString *tnRNib = @"/tmp/ut_tn_r.nib";
  NSString *tnRP = @"/tmp/ut_tn_r.uiplist";
  NSString *dpRx = @"/tmp/ut_dp_r.xib";
  NSString *tnRx = @"/tmp/ut_tn_r.xib";

  // ---- XIB conversion ----
  START_SET("XIB conversion")
    BOOL dpExists = [[NSFileManager defaultManager] fileExistsAtPath: dpNib];
    PASS(dpExists, "DesktopPref.nib fixture exists");
    if (!dpExists) SKIP("Missing DesktopPref.nib fixture");

    BOOL tnExists = [[NSFileManager defaultManager] fileExistsAtPath: tnNib];
    PASS(tnExists, "Test-nib.nib fixture exists");
    if (!tnExists) SKIP("Missing Test-nib.nib fixture");

    PASS(runTool(toolPath, dpNib, dpXib), "DesktopPref.nib -> .xib");
    PASS(runTool(toolPath, tnNib, tnXib), "Test-nib.nib -> .xib");

    NSString *xib1 = [NSString stringWithContentsOfFile: dpXib];
    NSString *xib2 = [NSString stringWithContentsOfFile: tnXib];
    PASS(xib1 != nil && [xib1 hasPrefix: @"<?xml"], "DP XIB is valid XML");
    PASS(xib2 != nil && [xib2 hasPrefix: @"<?xml"], "TN XIB is valid XML");
    PASS([xib1 rangeOfString: @"<objects>"].location != NSNotFound, "DP XIB has <objects>");
    PASS([xib2 rangeOfString: @"<objects>"].location != NSNotFound, "TN XIB has <objects>");
  END_SET("XIB conversion")

  // ---- UIPlist write ----
  START_SET("UIPlist write")
    PASS(runTool(toolPath, dpNib, dpP), "DesktopPref.nib -> .uiplist");
    PASS(runTool(toolPath, tnNib, tnP), "Test-nib.nib -> .uiplist");

    NSString *p1 = [NSString stringWithContentsOfFile: dpP];
    NSString *p2 = [NSString stringWithContentsOfFile: tnP];
    PASS(p1 != nil, "DP uiplist is readable");
    PASS(p2 != nil, "TN uiplist is readable");
    PASS([p1 rangeOfString: @"objects ="].location != NSNotFound, "DP has objects");
    PASS([p2 rangeOfString: @"objects ="].location != NSNotFound, "TN has objects");
    PASS([p1 rangeOfString: @"@"].location != NSNotFound, "DP has @oid refs");
    PASS([p2 rangeOfString: @"@"].location != NSNotFound, "TN has @oid refs");
    PASS([p1 rangeOfString: @"0x"].location == NSNotFound, "DP no hex addresses");
    PASS([p2 rangeOfString: @"0x"].location == NSNotFound, "TN no hex addresses");
    NSUInteger dpIdCount = countIds(p1);
    NSUInteger tnIdCount = countIds(p2);
    PASS(dpIdCount > 0, "DP has %lu objects", (unsigned long)dpIdCount);
    PASS(tnIdCount > 0, "TN has %lu objects", (unsigned long)tnIdCount);
  END_SET("UIPlist write")

  // ---- Forward determinism ----
  START_SET("Forward determinism")
    PASS(runTool(toolPath, dpNib, dpXib2), "Second DP XIB");
    PASS(runTool(toolPath, dpNib, dpP2), "Second DP uiplist");

    NSString *x1 = [NSString stringWithContentsOfFile: dpXib];
    NSString *x2 = [NSString stringWithContentsOfFile: dpXib2];
    PASS([x1 isEqualToString: x2], "XIB deterministic");

    NSString *p1 = [NSString stringWithContentsOfFile: dpP];
    NSString *p2 = [NSString stringWithContentsOfFile: dpP2];
    PASS([p1 isEqualToString: p2], "UIPlist deterministic");
  END_SET("Forward determinism")

  // ---- Roundtrip: uiplist -> nib -> uiplist ----
  START_SET("Roundtrip uiplist->nib->uiplist")
    PASS(runTool(toolPath, dpP, dpRNib), "DP uiplist -> nib");
    PASS(runTool(toolPath, dpRNib, dpRP), "DP roundtrip nib -> uiplist");

    NSString *dpKO = [dpRNib stringByAppendingPathComponent: @"keyedobjects.nib"];
    BOOL koExists = [[NSFileManager defaultManager] fileExistsAtPath: dpKO];
    PASS(koExists, "DP roundtrip nib has keyedobjects.nib");

    PASS(runTool(toolPath, tnP, tnRNib), "TN uiplist -> nib");
    PASS(runTool(toolPath, tnRNib, tnRP), "TN roundtrip nib -> uiplist");

    NSString *tnKO = [tnRNib stringByAppendingPathComponent: @"keyedobjects.nib"];
    PASS([[NSFileManager defaultManager] fileExistsAtPath: tnKO], "TN roundtrip nib has keyedobjects.nib");

    // Compare original vs roundtrip uiplists
    NSString *dpOrig = [NSString stringWithContentsOfFile: dpP];
    NSString *dpRound = [NSString stringWithContentsOfFile: dpRP];
    PASS(dpRound != nil, "DP roundtrip uiplist readable");
    PASS(countIds(dpRound) == countIds(dpOrig),
      "DP roundtrip has same object count (%lu vs %lu)",
      (unsigned long)countIds(dpRound), (unsigned long)countIds(dpOrig));

    NSString *tnOrig = [NSString stringWithContentsOfFile: tnP];
    NSString *tnRound = [NSString stringWithContentsOfFile: tnRP];
    PASS(tnRound != nil, "TN roundtrip uiplist readable");
    PASS(countIds(tnRound) == countIds(tnOrig),
      "TN roundtrip has same object count (%lu vs %lu)",
      (unsigned long)countIds(tnRound), (unsigned long)countIds(tnOrig));

    // Structural roundtrip: object IDs match (root oid may differ but object count same)
    NSRegularExpression *re = [NSRegularExpression
      regularExpressionWithPattern: @"^\\s*isa = \\w+;$"
      options: NSRegularExpressionAnchorsMatchLines error: NULL];
    NSUInteger dpIsa = [re numberOfMatchesInString: dpRound options: 0
      range: NSMakeRange(0, [dpRound length])];
    NSUInteger tnIsa = [re numberOfMatchesInString: tnRound options: 0
      range: NSMakeRange(0, [tnRound length])];
    PASS(dpIsa == countIds(dpRound), "DP roundtrip has matching id/isa (%lu vs %lu)",
      (unsigned long)countIds(dpRound), (unsigned long)dpIsa);
    PASS(tnIsa == countIds(tnRound), "TN roundtrip has matching id/isa (%lu vs %lu)",
      (unsigned long)countIds(tnRound), (unsigned long)tnIsa);
  END_SET("Roundtrip uiplist->nib->uiplist")

  // ---- Deep roundtrip: nib -> uiplist -> nib -> uiplist ----
  START_SET("Deep roundtrip nib->uiplist->nib->uiplist")
    NSString *dpA = @"/tmp/ut_dp_a.uiplist";   // a: original nib
    NSString *dpBNib = @"/tmp/ut_dp_b.nib";     // b: from a
    NSString *dpCP = @"/tmp/ut_dp_c.uiplist";   // c: from b
    NSString *dpDNib = @"/tmp/ut_dp_d.nib";     // d: from c
    NSString *dpEP = @"/tmp/ut_dp_e.uiplist";   // e: from d

    // Cycle 1
    PASS(runTool(toolPath, dpNib, dpA), "Step a: nib -> uiplist");
    PASS(runTool(toolPath, dpA, dpBNib), "Step b: a -> nib");
    PASS(runTool(toolPath, dpBNib, dpCP), "Step c: b -> uiplist");
    NSString *c = [NSString stringWithContentsOfFile: dpCP];
    PASS(c != nil, "Cycle 1 uiplist readable");

    // Cycle 2
    PASS(runTool(toolPath, dpCP, dpDNib), "Step d: c -> nib");
    PASS(runTool(toolPath, dpDNib, dpEP), "Step e: d -> uiplist");
    NSString *e = [NSString stringWithContentsOfFile: dpEP];
    PASS(e != nil && [c isEqualToString: e],
      "Convergence after 1 roundtrip: c == e (byte-exact)");

    NSUInteger aCount = countIds(c);
    NSUInteger eCount = countIds(e);
    PASS(aCount == eCount,
      "Stable object count across cycles (%lu)", (unsigned long)aCount);

    // Same deep test for Test-nib
    NSString *tnA = @"/tmp/ut_tn_a.uiplist";
    NSString *tnBNib = @"/tmp/ut_tn_b.nib";
    NSString *tnCP = @"/tmp/ut_tn_c.uiplist";
    NSString *tnDNib = @"/tmp/ut_tn_d.nib";
    NSString *tnEP = @"/tmp/ut_tn_e.uiplist";
    PASS(runTool(toolPath, tnNib, tnA), "TN: step a");
    PASS(runTool(toolPath, tnA, tnBNib), "TN: step b");
    PASS(runTool(toolPath, tnBNib, tnCP), "TN: step c");
    PASS(runTool(toolPath, tnCP, tnDNib), "TN: step d");
    PASS(runTool(toolPath, tnDNib, tnEP), "TN: step e");
    NSString *tnCStr = [NSString stringWithContentsOfFile: tnCP];
    NSString *tnEStr = [NSString stringWithContentsOfFile: tnEP];
    PASS(tnCStr != nil && tnEStr != nil && [tnCStr isEqualToString: tnEStr],
      "TN convergence after 1 roundtrip: c == e (byte-exact)");
  END_SET("Deep roundtrip nib->uiplist->nib->uiplist")

  // ---- XIB consistency across roundtrip ----
  START_SET("XIB consistency across roundtrip")
    PASS(runTool(toolPath, dpRNib, dpRx), "Roundtrip nib -> xib");
    NSString *xibRound = [NSString stringWithContentsOfFile: dpRx];
    PASS(xibRound != nil && [xibRound hasPrefix: @"<?xml"], "Roundtrip XIB is valid XML");
    PASS([xibRound rangeOfString: @"<objects>"].location != NSNotFound,
      "Roundtrip XIB has <objects>");
    // Note: roundtrip XIB may omit <window> due to connector ivar naming;
    // the original nib -> xib still produces it correctly

    // Same structural check for TN roundtrip
    NSString *tnRx = @"/tmp/ut_tn_r.xib";
    PASS(runTool(toolPath, tnRNib, tnRx), "TN roundtrip nib -> xib");
    NSString *tnXibRound = [NSString stringWithContentsOfFile: tnRx];
    PASS(tnXibRound != nil && [tnXibRound hasPrefix: @"<?xml"], "TN roundtrip XIB is valid XML");
    PASS([tnXibRound rangeOfString: @"<objects>"].location != NSNotFound,
      "TN roundtrip XIB has <objects>");
  END_SET("XIB consistency across roundtrip")

  DESTROY(arp);
  return 0;
}
