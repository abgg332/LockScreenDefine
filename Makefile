#
# 锁屏定义 (LockScreenDefine) —— 自定义锁屏通知宽度
#
# 构建（默认 = 隐根 / RootHide）：
#   $ make package FINALPACKAGE=1
#
# 切换打包方案：
#   $ make package FINALPACKAGE=1 PACKAGE_SCHEME=rootless   # 固定 /var/jb
#   $ make package FINALPACKAGE=1 PACKAGE_SCHEME=rootful    # 传统根
#
# 前提：roothide 版 Theos（与原版 100% 兼容，且支持三种 scheme）
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/roothide/theos/master/bin/install-theos)"
#

TARGET := iphone:clang:16.5:15.0
ARCHS  := arm64 arm64e

INSTALL_TARGET_PROCESSES = SpringBoard NotificationCenter

# ── 打包方案 ────────────────────────────────────────────────
#   roothide : 隐根，越狱根为随机目录，路径靠 jbroot() 解析
#   rootless : 固定 /var/jb
#   rootful  : 传统根，直接装到真实根
PACKAGE_SCHEME ?= roothide

ifeq ($(PACKAGE_SCHEME),rootful)
# rootful 需要显式清空 scheme，否则 Theos 会按 rootless 打包
export THEOS_PACKAGE_SCHEME =
else
export THEOS_PACKAGE_SCHEME = $(PACKAGE_SCHEME)
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LockScreenDefine
LockScreenDefine_FILES = Tweak/LockScreenDefine.xm
LockScreenDefine_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-function \
                          -I$(THEOS_PROJECT_DIR)/Shared
LockScreenDefine_FRAMEWORKS = UIKit Foundation

# 隐根下 tweak 默认受沙盒限制，需要放开（见 roothide/Developer: entitlements.md）
LockScreenDefine_CODESIGN_FLAGS = -S$(THEOS_PROJECT_DIR)/Tweak/LockScreenDefine.entitlements

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Prefs
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 SpringBoard"
