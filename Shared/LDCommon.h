#ifndef LDCOMMON_H
#define LDCOMMON_H

//
//  LDCommon.h
//  锁屏定义 —— Tweak 与设置面板共用的常量与路径解析
//
//  隐根（RootHide / Dopamine 2 roothide）适配说明
//  ------------------------------------------------
//  RootHide 的越狱根目录是一个每次越狱都会变的随机名字（不是固定的 /var/jb），
//  所以任何“写死 /var/jb/...”或“写死 /var/mobile/Library/Preferences/...”的做法都会失效。
//  官方推荐：
//    #include <roothide.h>
//    NSString *p = jbroot(@"/var/mobile/Library/Preferences/xxx.plist");
//  在 rootful / rootless 下，roothide/theos 会把 jbroot 编译成直通桩函数。
//
//  本文件用 __has_include 做条件编译：
//    · 有 roothide.h（roothide/theos 环境）  -> 直接用 jbroot()
//    · 没有（普通 theos / 想在别处编译）     -> 按 THEOS_PACKAGE_SCHEME 回退到 /var/jb 或 rootfs
//
//  关于配置存放位置：
//  RootHide 的 sandbox 规则里，tweak 只能自由写 jbroot 下的 /var/ 目录
//  （entitlements.md：“except for /var/ in jbroot, your tweak may not be able to
//   modify files in other jailbreak directories”），
//  因此配置统一放在 jbroot:/var/mobile/Library/Preferences/ 下，
//  Settings 的偏好 bundle 与 SpringBoard 中的 tweak 读的是同一份文件。
//

#import <Foundation/Foundation.h>

#if __has_include(<roothide.h>)
#import <roothide.h>
#define LD_HAS_ROOTHIDE 1
#endif

// ───────────────────────────────────── 配置键

static NSString *const LDKeyEnabled   = @"Enabled";
static NSString *const LDKeyWidth     = @"Width";
static NSString *const LDKeyiPadWidth = @"iPadWidth";

static NSString *const LDNotifyReload = @"com.lockdefine.prefs/Reload";

static const double LDWidthDefault      = 92.0;   // iPhone 默认
static const double LDWidthDefaultPad   = 76.0;   // iPad 默认
static const double LDWidthMin          = 50.0;
static const double LDWidthMax          = 100.0;

// ───────────────────────────────────── 路径

/// 把“越狱内的绝对路径”解析成当前越狱环境下真正可用的路径
static inline NSString *LDResolveJailbreakPath(NSString *path) {
#ifdef LD_HAS_ROOTHIDE
    return jbroot(path);
#else
    #if defined(THEOS_PACKAGE_SCHEME_ROOTLESS)
        return [@"/var/jb" stringByAppendingString:path];
    #else
        return path;   // rootful：直接就是真实路径
    #endif
#endif
}

/// 配置文件的完整路径（只算一次）
static inline NSString *LDPrefsPath(void) {
    static NSString *cached = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cached = LDResolveJailbreakPath(@"/var/mobile/Library/Preferences/com.lockdefine.prefs.plist");
    });
    return cached;
}

// ───────────────────────────────────── 设备

static inline BOOL LDIsPadDevice(void) {
    return [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
}

static inline NSString *LDCurrentWidthKey(void) {
    return LDIsPadDevice() ? LDKeyiPadWidth : LDKeyWidth;
}

static inline double LDDefaultWidthForDevice(void) {
    return LDIsPadDevice() ? LDWidthDefaultPad : LDWidthDefault;
}

// ───────────────────────────────────── 读写

static inline NSDictionary *LDReadPrefsDict(void) {
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:LDPrefsPath()];
    return [dict isKindOfClass:[NSDictionary class]] ? dict : nil;
}

static inline NSMutableDictionary *LDReadPrefsMutable(void) {
    NSDictionary *dict = LDReadPrefsDict();
    return dict ? [dict mutableCopy] : [NSMutableDictionary dictionary];
}

/// 写入配置并向 tweak 广播重载通知
static inline BOOL LDWritePrefsDict(NSDictionary *dict) {
    NSString *path = LDPrefsPath();
    NSString *dir  = [path stringByDeletingLastPathComponent];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dir]) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    }
    BOOL ok = [dict writeToFile:path atomically:YES];
    if (!ok) {
        NSLog(@"[LockScreenDefine] 写入配置失败: %@", path);
    }
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)LDNotifyReload,
                                         NULL, NULL, true);
    return ok;
}

static inline double LDClampWidth(double w) {
    if (!(w >= LDWidthMin)) w = LDWidthMin;
    if (w > LDWidthMax)     w = LDWidthMax;
    return w;
}

static inline double LDCurrentWidth(void) {
    id v = LDReadPrefsDict()[LDCurrentWidthKey()];
    return LDClampWidth(v ? [v doubleValue] : LDDefaultWidthForDevice());
}

/// 未安装过配置时默认开启（装上即可见效果）
static inline BOOL LDCurrentEnabled(void) {
    NSDictionary *dict = LDReadPrefsDict();
    if (!dict) return YES;
    id v = dict[LDKeyEnabled];
    return v ? [v boolValue] : YES;
}

#endif /* LDCOMMON_H */
