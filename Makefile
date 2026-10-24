TARGET := iphone:clang:16.5:15.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = Facebook

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MooDfacebook
MooDfacebook_FILES = Tweak.x
MooDfacebook_CFLAGS = -fobjc-arc -Wno-error -Wno-deprecated-declarations -Wno-unused-variable -Wno-logical-op-parentheses -Wno-unused-value
MooDfacebook_FRAMEWORKS = UIKit Foundation AVFoundation CoreMedia

include $(THEOS_MAKE_PATH)/tweak.mk
