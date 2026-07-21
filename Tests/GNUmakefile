include $(GNUSTEP_MAKEFILES)/common.make

TOOL_NAME = nib2xib_test

nib2xib_test_OBJC_FILES = test_basic.m
nib2xib_test_TOOL_LIBS = -lgnustep-base

ADDITIONAL_CPPFLAGS += -I$(GNUSTEP_MAKEFILES)/TestFramework

include $(GNUSTEP_MAKEFILES)/tool.make

internal-check:: all
	./obj/$(TOOL_NAME)
