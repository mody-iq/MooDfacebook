TARGET := iphone:clang:latest:15.0
ARCHS = arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = MooDfacebookPrefs

MooDfacebookPrefs_FILES = MooDfacebookRootListController.m
MooDfacebookPrefs_FRAMEWORKS = UIKit
MooDfacebookPrefs_PRIVATE_FRAMEWORKS = Preferences
MooDfacebookPrefs_INSTALL_PATH = /Library/PreferenceBundles
MooDfacebookPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/MooDfacebook.plist$(ECHO_END)
