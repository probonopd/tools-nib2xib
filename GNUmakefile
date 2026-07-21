include $(GNUSTEP_MAKEFILES)/common.make

TOOL_NAME = uiconvert

uiconvert_OBJC_FILES = \
	uiconvert_main.m \
	NIBParser.m \
	NSIBObjectData.m \
	XMLDocument.m \
	XMLElement.m \
	XMLNode.m \
	NSWindowTemplate.m \
	NSMenuTemplate.m \
	NSCustomObject.m \
	NSString_Additions.m \
	NSView_Additions.m \
	NSObject_KeyExtraction.m \
	NSMenuItem_Additions.m \
	NSIBConnector.m \
	NSMatrix_Additions.m \
	NSCell_Additions.m \
	NSBox_Additions.m \
	NSMenu_Additions.m \
	UIPlistWriter.m \
	UIPlistReader.m

uiconvert_TOOL_LIBS = -lgnustep-gui -lgnustep-base

include $(GNUSTEP_MAKEFILES)/tool.make

check::
	$(MAKE) -C Tests check
