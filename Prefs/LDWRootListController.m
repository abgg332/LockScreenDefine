//
//  LDWRootListController.m
//  锁屏定义 —— 设置入口
//
//  设计说明
//  --------
//  PreferenceLoader 只认 PSListController 的子孙类作为入口，所以这里继承 PSListController；
//  但界面完全自绘，不依赖 Cephei / Preferences 的头文件，也不碰 PSListController 的私有 ivar，
//  在隐根（RootHide）下编译与运行都更稳。
//
//  界面结构：预览卡片 → 开关 → 宽度滑块 → 恢复默认 → 说明
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "LDCommon.h"

// PreferenceLoader 需要这个基类；本工程不链接 Preferences 框架，用弱声明即可
@interface PSListController : UIViewController
@end

// ───────────────────────────────────────────── 颜色
// 最低部署版本为 iOS 15，下面这些语义色 API 自 iOS 13 起可用，无需再做版本判断

static UIColor *LDGroupBG(void) {
    return [UIColor systemGroupedBackgroundColor];
}

static UIColor *LDCardBG(void) {
    return [UIColor secondarySystemGroupedBackgroundColor];
}

static UIColor *LDLabel2(void) {
    return [UIColor secondaryLabelColor];
}

static UIColor *LDLabel1(void) {
    return [UIColor labelColor];
}

static UIColor *LDSeparator(void) {
    return [UIColor separatorColor];
}

static UIColor *LDAccent(void) {
    return [UIColor systemBlueColor];
}

// ───────────────────────────────────────────── 预览条

/// 一条示意用的“通知条”：圆角卡片 + 图标块 + 两行文字占位
@interface LDPreviewBar : UIView
@property (nonatomic, assign) CGFloat widthRatio;   // 0.5 ~ 1.0
@end

@implementation LDPreviewBar {
    NSLayoutConstraint *_widthConstraint;
    UIView *_icon;
    UIView *_line1;
    UIView *_line2;
}

- (instancetype)initWithLines:(NSInteger)lines {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;

    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.backgroundColor = LDGroupBG();
    self.layer.cornerRadius = 10;
    self.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
    self.layer.borderColor = [LDSeparator() colorWithAlphaComponent:0.6].CGColor;

    _icon = [[UIView alloc] initWithFrame:CGRectZero];
    _icon.translatesAutoresizingMaskIntoConstraints = NO;
    _icon.backgroundColor = LDAccent();
    _icon.alpha = 0.8;
    _icon.layer.cornerRadius = 4;
    [self addSubview:_icon];

    _line1 = [[UIView alloc] initWithFrame:CGRectZero];
    _line1.translatesAutoresizingMaskIntoConstraints = NO;
    _line1.backgroundColor = LDLabel2();
    _line1.alpha = 0.45;
    _line1.layer.cornerRadius = 2.5;
    [self addSubview:_line1];

    [NSLayoutConstraint activateConstraints:@[
        [_icon.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
        [_icon.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_icon.widthAnchor constraintEqualToConstant:16],
        [_icon.heightAnchor constraintEqualToConstant:16],

        [_line1.leadingAnchor constraintEqualToAnchor:_icon.trailingAnchor constant:8],
        [_line1.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-8],
        [_line1.heightAnchor constraintEqualToConstant:5],
        [_line1.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.55],
        [_line1.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-3],
    ]];

    if (lines > 1) {
        _line2 = [[UIView alloc] initWithFrame:CGRectZero];
        _line2.translatesAutoresizingMaskIntoConstraints = NO;
        _line2.backgroundColor = LDLabel2();
        _line2.alpha = 0.3;
        _line2.layer.cornerRadius = 2.5;
        [self addSubview:_line2];
        [NSLayoutConstraint activateConstraints:@[
            [_line2.leadingAnchor constraintEqualToAnchor:_line1.leadingAnchor],
            [_line2.heightAnchor constraintEqualToConstant:5],
            [_line2.widthAnchor constraintEqualToAnchor:self.widthAnchor multiplier:0.32],
            [_line2.topAnchor constraintEqualToAnchor:_line1.bottomAnchor constant:5],
        ]];
    }

    _widthConstraint = [self.widthAnchor constraintEqualToConstant:200];
    _widthConstraint.priority = UILayoutPriorityRequired;
    _widthConstraint.active = YES;

    return self;
}

- (void)setWidthRatio:(CGFloat)widthRatio {
    _widthRatio = widthRatio;
    [self.superview layoutIfNeeded];
    CGFloat available = self.superview.bounds.size.width - 20.0;
    if (available <= 0) available = 300;
    _widthConstraint.constant = MAX(60, available * widthRatio);
    [UIView animateWithDuration:0.15 animations:^{
        [self.superview layoutIfNeeded];
    }];
}

@end

// ───────────────────────────────────────────── 设置页

@interface LDWRootListController : PSListController
@end

@implementation LDWRootListController {
    LDPreviewBar *_previewBar1;
    LDPreviewBar *_previewBar2;
    UISwitch     *_toggle;
    UISlider     *_slider;
    UILabel      *_valueLabel;
    UIView       *_sliderBlock;
    BOOL          _pendingWrite;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"锁屏定义";
    self.view.backgroundColor = LDGroupBG();
    if (@available(iOS 11.0, *)) {
        self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    }
    [self buildInterface];
    [self refresh];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refresh];
}

#pragma mark - 界面搭建

- (void)buildInterface {
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    [self.view addSubview:scroll];

    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 24.0;
    [scroll addSubview:stack];

    CGFloat m = 20.0;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:scroll.topAnchor constant:20],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:-36],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor constant:m],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.trailingAnchor constant:-m],
        [stack.widthAnchor constraintEqualToAnchor:scroll.widthAnchor constant:-m * 2],
    ]];

    for (UIView *v in [self buildSections]) {
        [stack addArrangedSubview:v];
    }
}

- (NSArray<UIView *> *)buildSections {
    return @[
        [self buildPreviewSection],
        [self buildSwitchSection],
        [self buildSliderSection],
        [self buildResetCard],
        [self buildFooter],
    ];
}

- (UIView *)buildPreviewSection {
    UIView *wrapper = [[UIView alloc] initWithFrame:CGRectZero];

    UILabel *header = [[UILabel alloc] initWithFrame:CGRectZero];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.text = @"预览";
    header.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    header.textColor = LDLabel2();

    UIView *card = [self makeCard];

    _previewBar1 = [[LDPreviewBar alloc] initWithLines:2];
    _previewBar2 = [[LDPreviewBar alloc] initWithLines:1];
    _previewBar1.translatesAutoresizingMaskIntoConstraints = NO;
    _previewBar2.translatesAutoresizingMaskIntoConstraints = NO;

    [card addSubview:_previewBar1];
    [card addSubview:_previewBar2];

    UILabel *caption = [[UILabel alloc] initWithFrame:CGRectZero];
    caption.translatesAutoresizingMaskIntoConstraints = NO;
    caption.text = @"宽度按“可用宽度百分比”计算，100% 即系统默认";
    caption.font = [UIFont systemFontOfSize:11.5];
    caption.textColor = LDLabel2();
    caption.textAlignment = NSTextAlignmentCenter;
    caption.numberOfLines = 0;

    [wrapper addSubview:header];
    [wrapper addSubview:card];
    [wrapper addSubview:caption];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:wrapper.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:wrapper.leadingAnchor constant:4],
        [header.trailingAnchor constraintEqualToAnchor:wrapper.trailingAnchor],

        [card.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:8],
        [card.leadingAnchor constraintEqualToAnchor:wrapper.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:wrapper.trailingAnchor],

        [_previewBar1.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [_previewBar1.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [_previewBar1.heightAnchor constraintEqualToConstant:52],

        [_previewBar2.topAnchor constraintEqualToAnchor:_previewBar1.bottomAnchor constant:10],
        [_previewBar2.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [_previewBar2.heightAnchor constraintEqualToConstant:36],
        [_previewBar2.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],

        [caption.topAnchor constraintEqualToAnchor:card.bottomAnchor constant:8],
        [caption.leadingAnchor constraintEqualToAnchor:wrapper.leadingAnchor constant:4],
        [caption.trailingAnchor constraintEqualToAnchor:wrapper.trailingAnchor constant:-4],
        [caption.bottomAnchor constraintEqualToAnchor:wrapper.bottomAnchor],
    ]];

    return wrapper;
}

- (UIView *)buildSwitchSection {
    UIView *card = [self makeCard];
    UIView *row = [[UIView alloc] initWithFrame:CGRectZero];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"启用宽度自定义";
    title.font = [UIFont systemFontOfSize:17];
    title.textColor = LDLabel1();

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectZero];
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    sub.text = @"关闭后恢复系统默认宽度";
    sub.font = [UIFont systemFontOfSize:12];
    sub.textColor = LDLabel2();

    UIStackView *labels = [[UIStackView alloc] initWithArrangedSubviews:@[title, sub]];
    labels.translatesAutoresizingMaskIntoConstraints = NO;
    labels.axis = UILayoutConstraintAxisVertical;
    labels.spacing = 3;

    _toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
    _toggle.translatesAutoresizingMaskIntoConstraints = NO;
    [_toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    [_toggle setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [_toggle setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    [row addSubview:labels];
    [row addSubview:_toggle];
    [card addSubview:row];

    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:card.topAnchor],
        [row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [row.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:56],

        [labels.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16],
        [labels.topAnchor constraintEqualToAnchor:row.topAnchor constant:12],
        [labels.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-12],
        [labels.trailingAnchor constraintLessThanOrEqualToAnchor:_toggle.leadingAnchor constant:-12],

        [_toggle.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16],
        [_toggle.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];

    return card;
}

- (UIView *)buildSliderSection {
    UIView *card = [self makeCard];

    _sliderBlock = [[UIView alloc] initWithFrame:CGRectZero];
    _sliderBlock.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"通知宽度";
    title.font = [UIFont systemFontOfSize:17];
    title.textColor = LDLabel1();

    _valueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightSemibold];
    _valueLabel.textAlignment = NSTextAlignmentRight;
    _valueLabel.textColor = LDAccent();
    [_valueLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [_valueLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *titleRow = [[UIStackView alloc] initWithArrangedSubviews:@[title, _valueLabel]];
    titleRow.axis = UILayoutConstraintAxisHorizontal;
    titleRow.spacing = 8;

    _slider = [[UISlider alloc] initWithFrame:CGRectZero];
    _slider.translatesAutoresizingMaskIntoConstraints = NO;
    _slider.minimumValue = LDWidthMin;
    _slider.maximumValue = LDWidthMax;
    _slider.continuous = YES;
    [_slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [_slider addTarget:self action:@selector(sliderCommitted:) forControlEvents:
        UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

    UILabel *left  = [self hintLabel:[NSString stringWithFormat:@"%.0f%%  更窄", LDWidthMin]
                           alignment:NSTextAlignmentLeft];
    UILabel *right = [self hintLabel:[NSString stringWithFormat:@"更宽  %.0f%%", LDWidthMax]
                           alignment:NSTextAlignmentRight];
    UIStackView *hints = [[UIStackView alloc] initWithArrangedSubviews:@[left, right]];
    hints.axis = UILayoutConstraintAxisHorizontal;
    hints.distribution = UIStackViewDistributionFillEqually;

    UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:@[titleRow, _slider, hints]];
    column.translatesAutoresizingMaskIntoConstraints = NO;
    column.axis = UILayoutConstraintAxisVertical;
    column.spacing = 10;

    [_sliderBlock addSubview:column];
    [card addSubview:_sliderBlock];

    [NSLayoutConstraint activateConstraints:@[
        [_sliderBlock.topAnchor constraintEqualToAnchor:card.topAnchor],
        [_sliderBlock.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [_sliderBlock.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [_sliderBlock.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],

        [column.topAnchor constraintEqualToAnchor:_sliderBlock.topAnchor constant:14],
        [column.leadingAnchor constraintEqualToAnchor:_sliderBlock.leadingAnchor constant:16],
        [column.trailingAnchor constraintEqualToAnchor:_sliderBlock.trailingAnchor constant:-16],
        [column.bottomAnchor constraintEqualToAnchor:_sliderBlock.bottomAnchor constant:-12],
    ]];

    return card;
}

- (UILabel *)hintLabel:(NSString *)text alignment:(NSTextAlignment)align {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.text = text;
    l.font = [UIFont systemFontOfSize:11];
    l.textColor = LDLabel2();
    l.textAlignment = align;
    return l;
}

- (UIView *)buildResetCard {
    UIView *card = [self makeCard];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:@"恢复默认设置" forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:17];
    button.tintColor = LDAccent();
    [button addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:button];

    [NSLayoutConstraint activateConstraints:@[
        [button.topAnchor constraintEqualToAnchor:card.topAnchor],
        [button.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [button.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [button.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [button.heightAnchor constraintEqualToConstant:50],
    ]];
    return card;
}

- (UIView *)buildFooter {
    UILabel *footer = [[UILabel alloc] initWithFrame:CGRectZero];
    footer.numberOfLines = 0;
    footer.font = [UIFont systemFontOfSize:12];
    footer.textColor = LDLabel2();
    footer.text = @"宽度作用于锁屏通知列表，下拉通知中心里的同一份列表也会同步。\n"
                   @"修改后立即生效；若锁屏未刷新，息屏再点亮一次即可。";
    return footer;
}

- (UIView *)makeCard {
    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = LDCardBG();
    card.layer.cornerRadius = 12;
    card.layer.masksToBounds = YES;
    return card;
}

#pragma mark - 交互

- (void)toggleChanged:(UISwitch *)sender {
    NSMutableDictionary *dict = LDReadPrefsMutable();
    dict[LDKeyEnabled] = @(sender.on);
    LDWritePrefsDict(dict);
    [self refresh];
}

- (void)sliderChanged:(UISlider *)sender {
    double v = round(sender.value);
    _valueLabel.text = [NSString stringWithFormat:@"%.0f%%", v];
    _previewBar1.widthRatio = v / 100.0;
    _previewBar2.widthRatio = v / 100.0;

    // 拖动过程中节流写盘（约 15fps），让锁屏实时看到变化
    if (!_pendingWrite) {
        _pendingWrite = YES;
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self->_pendingWrite = NO;
            NSMutableDictionary *dict = LDReadPrefsMutable();
            dict[LDCurrentWidthKey()] = @(round(self->_slider.value));
            LDWritePrefsDict(dict);
        });
    }
}

- (void)sliderCommitted:(UISlider *)sender {
    double v = round(sender.value);
    NSMutableDictionary *dict = LDReadPrefsMutable();
    dict[LDCurrentWidthKey()] = @(v);
    LDWritePrefsDict(dict);   // 松手再写一次，确保最终值落盘
}

- (void)resetTapped {
    NSMutableDictionary *dict = LDReadPrefsMutable();
    dict[LDKeyEnabled] = @(YES);
    dict[LDCurrentWidthKey()] = @(LDDefaultWidthForDevice());
    LDWritePrefsDict(dict);
    [self refresh];
}

#pragma mark - 刷新

- (void)refresh {
    double width = LDCurrentWidth();
    BOOL enabled = LDCurrentEnabled();

    _toggle.on = enabled;
    _slider.value = width;
    _slider.enabled = enabled;

    _valueLabel.text = [NSString stringWithFormat:@"%.0f%%", width];
    _valueLabel.textColor = enabled ? LDAccent() : LDLabel2();

    _sliderBlock.alpha = enabled ? 1.0 : 0.4;
    _sliderBlock.userInteractionEnabled = enabled;

    CGFloat ratio = enabled ? (width / 100.0) : 1.0;
    [_previewBar1.superview layoutIfNeeded];
    _previewBar1.widthRatio = ratio;
    _previewBar2.widthRatio = ratio;
}

@end
