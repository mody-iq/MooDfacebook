THEOS_PACKAGE_SCHEME = roothide
TARGET = iphone:clang:latest:15.0
ARCHS = arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MooDfacebook
MooDfacebook_FILES = Tweak.x Discovery.m
MooDfacebook_CFLAGS = -fobjc-arc
MooDfacebook_FRAMEWORKS = UIKit Foundation AVFoundation

include $(THEOS_MAKE_PATH)/tweak.mk
