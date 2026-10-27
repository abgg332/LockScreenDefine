//
//  LockScreenDefine.xm —— 锁屏定义
//  自定义锁屏通知宽度 / iOS 16 · Dopamine 2（隐根 roothide）
//
//  实现思路
//  --------
//  锁屏通知列表在 NotificationCenter 进程里是一个 UICollectionView，
//  每条通知是一个与容器等宽的 Cell。我们不依赖任何私有类名（小版本之间会变），
//  只钩公开的 UIKit 方法，并用“几何特征”筛出通知列表：
//
//    1. -[UICollectionView layoutAttributesForElementsInRect:]
//       在系统算好的 attributes 上按百分比改宽度并保持居中 ——
//       上屏时就是目标宽度，不会出现“先窄后宽”的抖动；
//    2. -[UICollectionView layoutSubviews] 兜底，处理已经上屏的 Cell；
//    3. -[UICollectionViewCell layoutSubviews] 再兜底，
//       Cell 自己重排把宽度改回系统默认值时再压回去；
//    4. 递归修正 Cell 内部横向撑满的子视图（contentView / 卡片背景），
//       否则外层 Cell 变宽了，里面的卡片仍是原宽度。
//
//  安全策略：只在“宽度接近满宽”、“高度大于 32pt”的竖直列表上生效，
//  设置页、App 列表等其它 UICollectionView 不会被误伤。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>

#import "LDCommon.h"

// ───────────────────────────────────────────── 全局状态

static BOOL   LDEnabled = YES;
static double LDWidth   = LDWidthDefault;

static BOOL LDShouldLog(void) {
    static int v = -1;
    if (v < 0) v = (getenv("LDDEBUG") != NULL) ? 1 : 0;
    return v == 1;
}

#define LDLog(...) do { if (LDShouldLog()) NSLog(@"[LockScreenDefine] " __VA_ARGS__); } while (0)

// 关联对象 key
static const void *kLDListKey      = &kLDListKey;       // UIView  -> NSNumber（已识别为通知列表）
static const void *kLDListLayerKey = &kLDListLayerKey;  // CALayer -> UIView（供向上回溯）

// ───────────────────────────────────────────── 配置

static void LDLoadPrefs(void) {
    NSDictionary *dict = LDReadPrefsDict();
    LDEnabled = dict ? ([dict[LDKeyEnabled] boolValue]) : YES;   // 首次安装默认开启

    id w = dict[LDCurrentWidthKey()];
    LDWidth = LDClampWidth(w ? [w doubleValue] : LDDefaultWidthForDevice());

    LDLog(@"prefs @ %@ -> enabled=%d width=%.0f", LDPrefsPath(), LDEnabled, LDWidth);
}

/// 1.0 = 系统默认宽度
static inline CGFloat LDWidthRatio(void) {
    if (!LDEnabled) return 1.0;
    return (CGFloat)(LDWidth / 100.0);
}

// ───────────────────────────────────────────── 工具

static BOOL LDIsLayoutAttributes(id obj) {
    static Class base = Nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ base = objc_getClass("UICollectionViewLayoutAttributes"); });
    if (!base || !obj) return NO;
    Class c = object_getClass(obj);
    for (int i = 0; i < 64 && c; i++) {
        if (c == base) return YES;
        c = class_getSuperclass(c);
    }
    return NO;
}

/// 列表可用宽度（扣掉安全区内边距）
static CGFloat LDContentWidth(UIView *list) {
    UIEdgeInsets insets = list.safeAreaInsets;
    CGFloat w = list.bounds.size.width - insets.left - insets.right;
    return (w > 0) ? w : list.bounds.size.width;
}

/// 是否是“锁屏通知列表”这类竖直大列表
static BOOL LDLooksLikeNotificationList(UIView *list) {
    if (![list isKindOfClass:[UICollectionView class]]) return NO;
    if (list.bounds.size.width < 120 || list.bounds.size.height < 32) return NO;
    if (![list.collectionViewLayout respondsToSelector:@selector(layoutAttributesForElementsInRect:)]) return NO;
    return YES;
}

/// 只有“接近满宽”的卡片才是通知，横向滑动的小组件不动
static BOOL LDIsNotificationCard(CGRect f, CGFloat containerWidth) {
    if (containerWidth <= 0) return NO;
    if (f.size.width < containerWidth * 0.4) return NO;
    if (f.size.width > containerWidth + 0.5) return NO;
    return YES;
}

static void LDRememberList(UIView *list) {
    if (!list) return;
    if (!objc_getAssociatedObject(list, kLDListKey)) {
        objc_setAssociatedObject(list, kLDListKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (list.layer && !objc_getAssociatedObject(list.layer, kLDListLayerKey)) {
        objc_setAssociatedObject(list.layer, kLDListLayerKey, list, OBJC_ASSOCIATION_ASSIGN);
    }
}

/// Cell 可能被系统包进内部容器，沿图层树向上找已识别的通知列表
static UIView *LDEnclosingList(UIView *view) {
    CALayer *cur = view.layer.superlayer;
    for (int i = 0; i < 16 && cur; i++) {
        id tagged = objc_getAssociatedObject(cur, kLDListLayerKey);
        if (tagged) return (UIView *)tagged;
        cur = cur.superlayer;
    }
    return nil;
}

// ───────────────────────────────────────────── 尺寸换算

/// 递归修正“横向撑满父视图”的子视图，让内部卡片跟着 Cell 一起变宽
static void LDResizeDescendants(UIView *view, CGSize oldSize, CGSize newSize, int depth) {
    if (!view || depth > 3) return;
    if (oldSize.width <= 0.5) return;

    for (UIView *sub in view.subviews) {
        CGRect f = sub.frame;
        BOOL fullW = fabs(f.size.width - oldSize.width) <= 1.5;
        BOOL fullH = fabs(f.size.height - oldSize.height) <= 1.5;
        if (!fullW) continue;          // 图标、时间等固定宽度元素保持不动

        CGRect nf = f;
        if (fullH) {
            nf = CGRectMake(0, 0, newSize.width, newSize.height);
        } else {
            nf.origin.x   = (oldSize.width > 0) ? newSize.width * (f.origin.x / oldSize.width) : f.origin.x;
            nf.size.width = newSize.width;
        }
        if (CGRectEqualToRect(nf, f)) continue;

        sub.frame = nf;
        LDResizeDescendants(sub, f.size, nf.size, depth + 1);
    }
}

/// 给一个 Cell 套用新宽度（水平居中）
static void LDApplyToCell(UIView *cell, UIView *list) {
    CGFloat containerWidth = LDContentWidth(list);
    if (containerWidth <= 0) return;
    if (!LDIsNotificationCard(cell.frame, containerWidth)) return;

    CGFloat newWidth = MIN(containerWidth, containerWidth * LDWidthRatio());
    if (fabs(newWidth - cell.frame.size.width) < 0.5) return;

    UIEdgeInsets insets = list.safeAreaInsets;
    CGRect oldFrame = cell.frame;
    CGRect newFrame = oldFrame;
    newFrame.size.width = newWidth;
    newFrame.origin.x   = insets.left + (containerWidth - newWidth) / 2.0;

    cell.frame = newFrame;
    LDResizeDescendants(cell, oldFrame.size, newFrame.size, 0);
}

// ───────────────────────────────────────────── 原始实现

static void (*orig_cvLayoutSubviews)(id, SEL);
static void (*orig_cellLayoutSubviews)(id, SEL);
static id   (*orig_layoutAttributes)(id, SEL, CGRect);

// ───────────────────────────────────────────── 钩子

static void ld_cvLayoutSubviews(id self, SEL _cmd) {
    orig_cvLayoutSubviews(self, _cmd);

    UIView *list = (UIView *)self;
    if (!LDLooksLikeNotificationList(list)) return;
    LDRememberList(list);              // 即使关闭也要标记，方便 Cell 钩子识别上下文
    if (!LDEnabled) return;

    CGFloat containerWidth = LDContentWidth(list);
    CGFloat newWidth = MIN(containerWidth, containerWidth * LDWidthRatio());
    UIEdgeInsets insets = list.safeAreaInsets;

    for (UIView *cell in [(UICollectionView *)list visibleCells]) {
        CGRect f = cell.frame;
        if (!LDIsNotificationCard(f, containerWidth)) continue;
        if (fabs(f.size.width - newWidth) < 0.5) continue;

        CGRect old = f;
        f.size.width = newWidth;
        f.origin.x   = insets.left + (containerWidth - newWidth) / 2.0;
        cell.frame = f;
        LDResizeDescendants(cell, old.size, f.size, 0);
    }
}

static void ld_lockscreendefine_cellLayout(id self, SEL _cmd) {
    orig_cellLayoutSubviews(self, _cmd);
    if (!LDEnabled) return;

    UIView *cell = (UIView *)self;
    UIView *list = LDEnclosingList(cell);
    if (!list) return;
    LDApplyToCell(cell, list);
}

static id ld_layoutAttributes(id self, SEL _cmd, CGRect rect) {
    id result = orig_layoutAttributes(self, _cmd, rect);
    if (![result isKindOfClass:[NSArray class]]) return result;

    UIView *list = (UIView *)self;
    if (!LDLooksLikeNotificationList(list)) return result;
    if (!LDEnabled) return result;

    CGFloat ratio = LDWidthRatio();
    if (fabs(ratio - 1.0) < 0.001) {
        LDRememberList(list);
        return result;
    }

    UIEdgeInsets insets = list.safeAreaInsets;
    CGFloat containerWidth = LDContentWidth(list);
    CGFloat newWidth = MIN(containerWidth, containerWidth * ratio);
    BOOL touched = NO;

    for (id attr in (NSArray *)result) {
        if (!LDIsLayoutAttributes(attr)) continue;

        CGRect f = ((CGRect (*)(id, SEL))objc_msgSend)(attr, @selector(frame));
        if (!LDIsNotificationCard(f, containerWidth)) continue;
        if (fabs(newWidth - f.size.width) < 0.5) continue;

        f.size.width = newWidth;
        f.origin.x   = insets.left + (containerWidth - newWidth) / 2.0;
        ((void (*)(id, SEL, CGRect))objc_msgSend)(attr, @selector(setFrame:), f);
        touched = YES;
    }

    if (touched) LDRememberList(list);
    return result;
}

// ───────────────────────────────────────────── 刷新

static void LDRefresh(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplication *app = [UIApplication sharedApplication];
        if (![app respondsToSelector:@selector(connectedScenes)]) return;
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                [window setNeedsLayout];
                [window layoutIfNeeded];
            }
        }
    });
}

static void LDOnPrefsChanged(CFNotificationCenterRef center, void *observer,
                             CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    LDLoadPrefs();
    LDRefresh();
}

// ───────────────────────────────────────────── 入口

__attribute__((constructor))
static void LDInitialize(void) {
    @autoreleasepool {
        LDLoadPrefs();

        Class cvClass   = objc_getClass("UICollectionView");
        Class cellClass = objc_getClass("UICollectionViewCell");

        if (cvClass) {
            Method m = class_getInstanceMethod(cvClass, @selector(layoutSubviews));
            if (m) {
                orig_cvLayoutSubviews = (void *)method_getImplementation(m);
                method_setImplementation(m, (IMP)ld_cvLayoutSubviews);
            }
            Method m2 = class_getInstanceMethod(cvClass, NSSelectorFromString(@"layoutAttributesForElementsInRect:"));
            if (m2) {
                orig_layoutAttributes = (void *)method_getImplementation(m2);
                method_setImplementation(m2, (IMP)ld_layoutAttributes);
            }
        }

        if (cellClass) {
            // Cell 一般没有自己实现 layoutSubviews，先按 UIView 的签名补一个再替换，
            // 避免直接改到 UIView 上影响全局
            Method m = class_getInstanceMethod(cellClass, @selector(layoutSubviews));
            if (m) {
                orig_cellLayoutSubviews = (void *)method_getImplementation(m);
                class_addMethod(cellClass, NSSelectorFromString(@"ld_lockscreendefine_cellLayout"),
                                (IMP)ld_lockscreendefine_cellLayout, method_getTypeEncoding(m));
                Method ours = class_getInstanceMethod(cellClass, NSSelectorFromString(@"ld_lockscreendefine_cellLayout"));
                method_setImplementation(m, method_getImplementation(ours));
            }
        }

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL, LDOnPrefsChanged,
                                        (__bridge CFStringRef)LDNotifyReload,
                                        NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

        LDLog(@"loaded on iOS %@ (enabled=%d width=%.0f)", [[UIDevice currentDevice] systemVersion],
              LDEnabled, LDWidth);
    }
}
