include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = LockScreenDefinePrefs

LockScreenDefinePrefs_FILES = LDWRootListController.m
LockScreenDefinePrefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations \
                               -I$(THEOS_PROJECT_DIR)/../Shared
LockScreenDefinePrefs_FRAMEWORKS = UIKit Foundation
LockScreenDefinePrefs_INSTALL_PATH = /Library/PreferenceBundles
LockScreenDefinePrefs_PRIVATE_FRAMEWORKS = Preferences

# 隐根：preferences bundle 也要放开 sandbox，否则读不到 jbroot 里的配置
LockScreenDefinePrefs_CODESIGN_FLAGS = -S$(THEOS_PROJECT_DIR)/../Tweak/LockScreenDefine.entitlements

include $(THEOS_MAKE_PATH)/bundle.mk
