TARGET := iphone:clang:latest:15.0
ARCHS = arm64e

THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MooDfacebook

MooDfacebook_FILES = Tweak.x
MooDfacebook_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-deprecated-declarations
MooDfacebook_FRAMEWORKS = UIKit Foundation AVFoundation Photos QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
