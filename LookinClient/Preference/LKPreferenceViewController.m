//
//  LKPreferenceViewController.m
//  Lookin
//
//  Created by Li Kai on 2019/1/4.
//  https://lookin.work
//

#import "LKPreferenceViewController.h"
#import "LKMessageManager.h"
#import "LKNavigationManager.h"
#import "LKPreferenceManager.h"
#import "LKPreferencePopupView.h"
#import "LKPreferenceSwitchView.h"
#import "Lookin-Swift.h"

@interface LKPreferenceViewController ()

@property(nonatomic, strong) LKPreferencePopupView *view_doubleClick;
@property(nonatomic, strong) LKPreferencePopupView *view_appearance;
@property(nonatomic, strong) LKPreferencePopupView *view_colorFormat;
@property(nonatomic, strong) LKPreferenceSwitchView *view_enableLog;
@property(nonatomic, strong) LKPreferenceSwitchView *view_mcpServerEnabled;
@property(nonatomic, strong) NSTextField *mcpPortLabel;
@property(nonatomic, strong) NSTextField *mcpPortField;
@property(nonatomic, strong) NSSegmentedControl *aiAccessModeControl;
@property(nonatomic, strong) NSTextField *mcpConfigLabel;
@property(nonatomic, strong) NSButton *aiCommandCopyButton;
@property(nonatomic, copy) NSString *aiCopyValue;
@property(nonatomic, strong) LKPreferencePopupView *view_contrast;

//@property(nonatomic, strong) NSButton *debugButton;
@property(nonatomic, strong) NSButton *resetButton;

@end

@implementation LKPreferenceViewController

- (void)setView:(NSView *)view {
  [super setView:view];

  CGFloat controlX = IsEnglish ? 94 : 84;

  //    LKPreferenceManager *manager = [LKPreferenceManager mainManager];
  //
  //    @weakify(self);
  self.view_colorFormat = [[LKPreferencePopupView alloc]
      initWithTitle:NSLocalizedString(@"Color Format", nil)
           messages:@[
             NSLocalizedString(@"Color will be displayed in format like (255, "
                               @"12, 34, 0.5). Alpha value is between 0 and 1.",
                               nil),
             NSLocalizedString(@"Color will be displayed in format like "
                               @"#7e7e7eff. The components are #RRGGBBAA.",
                               nil)
           ]
            options:@[ @"RGBA", @"HEX" ]];
  self.view_colorFormat.buttonX = controlX;
  self.view_colorFormat.didChange = ^(NSUInteger selectedIndex) {
    [LKPreferenceManager mainManager].rgbaFormat =
        (selectedIndex == 0 ? YES : NO);
  };
  [self.view addSubview:self.view_colorFormat];

  NSString *contrastTips = NSLocalizedString(
      @"Adjust this option to use a deeper layer selection color.", nil);
  self.view_contrast = [[LKPreferencePopupView alloc]
      initWithTitle:NSLocalizedString(@"Image contrast", nil)
           messages:@[ contrastTips, contrastTips, contrastTips ]
            options:@[
              NSLocalizedString(@"Normal", nil),
              NSLocalizedString(@"Medium", nil), NSLocalizedString(@"High", nil)
            ]];
  self.view_contrast.buttonX = controlX;
  self.view_contrast.didChange = ^(NSUInteger selectedIndex) {
    [LKPreferenceManager mainManager].imageContrastLevel = selectedIndex;
  };
  [self.view addSubview:self.view_contrast];

  self.view_appearance = [[LKPreferencePopupView alloc]
      initWithTitle:NSLocalizedString(@"Appearance", nil)
            message:nil
            options:@[
              NSLocalizedString(@"Dark Mode", nil),
              NSLocalizedString(@"Light Mode", nil),
              NSLocalizedString(@"System Default", nil)
            ]];
  self.view_appearance.buttonX = controlX;
  self.view_appearance.didChange = ^(NSUInteger selectedIndex) {
    [LKPreferenceManager mainManager].appearanceType = selectedIndex;
  };
  [self.view addSubview:self.view_appearance];

  self.view_doubleClick = [[LKPreferencePopupView alloc]
      initWithTitle:NSLocalizedString(@"Double click", nil)
            message:nil
            options:@[
              NSLocalizedString(@"Expand or collapse layer", nil),
              NSLocalizedString(@"Focus on layer", nil)
            ]];
  self.view_doubleClick.buttonX = controlX;
  self.view_doubleClick.didChange = ^(NSUInteger selectedIndex) {
    [LKPreferenceManager mainManager].doubleClickBehavior = selectedIndex;
  };
  [self.view addSubview:self.view_doubleClick];

  self.view_enableLog = [[LKPreferenceSwitchView alloc]
      initWithTitle:NSLocalizedString(@"Share analytics with Lookin", nil)
            message:NSLocalizedString(
                        @"Help to improve Lookin by automatically sending "
                        @"diagnostics and usage data.",
                        nil)];
  self.view_enableLog.didChange = ^(BOOL isChecked) {
    [LKPreferenceManager mainManager].enableReport = isChecked;
  };
  [self.view addSubview:self.view_enableLog];

  self.view_mcpServerEnabled = [[LKPreferenceSwitchView alloc]
      initWithTitle:@"AI Integration"
            message:@"Expose the inspected hierarchy and screenshots to local MCP, "
                    @"CLI, and Skill workflows."];
  __weak typeof(self) weakSelf = self;
  self.view_mcpServerEnabled.didChange = ^(BOOL isChecked) {
    [LKPreferenceManager mainManager].mcpServerEnabled = isChecked;
    [[LKMCPManager sharedManager] toggleServerIfNeeded];
    [weakSelf _updateMcpConfigLabel];
  };
  [self.view addSubview:self.view_mcpServerEnabled];

  self.mcpPortLabel = [NSTextField labelWithString:@"端口 (Port):"];
  self.mcpPortLabel.font = [NSFont systemFontOfSize:13];
  self.mcpPortLabel.textColor = [NSColor labelColor];
  [self.view addSubview:self.mcpPortLabel];

  self.mcpPortField = [NSTextField textFieldWithString:@""];
  self.mcpPortField.font = [NSFont systemFontOfSize:13];
  self.mcpPortField.target = self;
  self.mcpPortField.action = @selector(_mcpPortChanged:);

  NSNumberFormatter *portFormatter = [[NSNumberFormatter alloc] init];
  portFormatter.usesGroupingSeparator = NO;
  self.mcpPortField.formatter = portFormatter;

  [self.view addSubview:self.mcpPortField];

  self.aiAccessModeControl =
      [NSSegmentedControl segmentedControlWithLabels:@[ @"MCP", @"CLI", @"Skill" ]
                                        trackingMode:NSSegmentSwitchTrackingSelectOne
                                              target:self
                                              action:@selector(_aiAccessModeChanged:)];
  self.aiAccessModeControl.selectedSegment = 0;
  [self.view addSubview:self.aiAccessModeControl];

  self.mcpConfigLabel = [NSTextField labelWithString:@""];
  self.mcpConfigLabel.font = [NSFont userFixedPitchFontOfSize:12];
  self.mcpConfigLabel.textColor = [NSColor secondaryLabelColor];
  self.mcpConfigLabel.selectable = YES;
  self.mcpConfigLabel.lineBreakMode = NSLineBreakByWordWrapping;
  [self.view addSubview:self.mcpConfigLabel];

  NSImage *copyImage = [NSImage imageWithSystemSymbolName:@"doc.on.doc"
                                accessibilityDescription:@"Copy"];
  self.aiCommandCopyButton = [NSButton buttonWithImage:copyImage
                                                target:self
                                                action:@selector(_copyAICommand:)];
  self.aiCommandCopyButton.bezelStyle = NSBezelStyleTexturedRounded;
  self.aiCommandCopyButton.toolTip = @"Copy setup command";
  [self.view addSubview:self.aiCommandCopyButton];

  //    self.debugButton = [NSButton lk_normalButtonWithTitle:@"Debug"
  //    target:self action:@selector(_handleDebugButton)]; [self.view
  //    addSubview:self.debugButton];

  self.resetButton =
      [NSButton lk_normalButtonWithTitle:NSLocalizedString(@"Reset", nil)
                                  target:self
                                  action:@selector(_handleResetButton)];
  [self.view addSubview:self.resetButton];

  [self renderFromPreferenceManager];
}

- (void)renderFromPreferenceManager {
  LKPreferenceManager *manager = [LKPreferenceManager mainManager];

  if (manager.rgbaFormat) {
    self.view_colorFormat.selectedIndex = 0;
  } else {
    self.view_colorFormat.selectedIndex = 1;
  }

  self.view_contrast.selectedIndex = manager.imageContrastLevel;

  self.view_appearance.selectedIndex = manager.appearanceType;
  self.view_doubleClick.selectedIndex = manager.doubleClickBehavior;
  self.view_enableLog.isChecked = manager.enableReport;
  self.view_mcpServerEnabled.isChecked = manager.mcpServerEnabled;
  self.mcpPortField.integerValue = manager.mcpServerPort;
  [self _updateMcpConfigLabel];
}

- (void)_mcpPortChanged:(NSTextField *)sender {
  NSInteger port = sender.integerValue;
  if (port > 0 && port <= 65535) {
    [LKPreferenceManager mainManager].mcpServerPort = port;
    [[LKMCPManager sharedManager] restartServerIfNeeded];
    [self _updateMcpConfigLabel];
  } else {
    sender.integerValue = [LKPreferenceManager mainManager].mcpServerPort;
  }
}

- (void)_updateMcpConfigLabel {
  NSInteger port = [LKPreferenceManager mainManager].mcpServerPort;
  LKMCPManager *manager = [LKMCPManager sharedManager];
  NSString *status = nil;
  if (manager.isRunning) {
    status = @"Running locally";
  } else if ([LKPreferenceManager mainManager].mcpServerEnabled) {
    status = @"Unavailable - check the selected port";
  } else {
    status = @"Off";
  }

  NSInteger mode = self.aiAccessModeControl.selectedSegment;
  NSString *detail = nil;
  if (mode == 1) {
    self.aiCopyValue = @"./bin/lookin capture --output .lookin-capture";
    detail = [NSString
        stringWithFormat:@"%@\nAPI  %@\n\n%@",
                         status, manager.apiServerURL, self.aiCopyValue];
  } else if (mode == 2) {
    self.aiCopyValue = @"$lookin-ui-debug";
    detail = [NSString
        stringWithFormat:@"%@\nGlobal skill  ~/.agents/skills/lookin-ui-debug\n\nInvoke  %@",
                         status, self.aiCopyValue];
  } else {
    self.aiCopyValue = [NSString
        stringWithFormat:@"codex mcp add lookin --url http://127.0.0.1:%@/mcp",
                         @(port)];
    detail = [NSString
        stringWithFormat:@"%@\nEndpoint  http://127.0.0.1:%@/mcp\n\n%@",
                         status, @(port), self.aiCopyValue];
  }
  self.mcpConfigLabel.stringValue = detail;
  self.aiCommandCopyButton.enabled = self.aiCopyValue.length > 0;
}

- (void)_aiAccessModeChanged:(NSSegmentedControl *)sender {
  [self _updateMcpConfigLabel];
  [self.view setNeedsLayout:YES];
}

- (void)_copyAICommand:(NSButton *)sender {
  if (self.aiCopyValue.length == 0) {
    return;
  }
  NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
  [pasteboard clearContents];
  [pasteboard setString:self.aiCopyValue forType:NSPasteboardTypeString];
}

- (void)viewDidLayout {
  [super viewDidLayout];

  NSEdgeInsets insets = NSEdgeInsetsMake(20, 30, 10, 30);

  $(self.view_appearance)
      .x(insets.left)
      .toRight(insets.right)
      .y(insets.top)
      .height(50);

  $(self.view_colorFormat)
      .x(insets.left)
      .toRight(insets.right)
      .y(self.view_appearance.$maxY)
      .height(80);
  $(self.view_contrast)
      .x(insets.left)
      .toRight(insets.right)
      .y(self.view_colorFormat.$maxY)
      .height(65);

  $(self.view_doubleClick)
      .x(insets.left)
      .toRight(insets.right)
      .y(self.view_contrast.$maxY)
      .height(50);

  __block CGFloat y = self.view_doubleClick.$maxY;

  $(self.view_enableLog).x(115).toRight(insets.right).y(y).heightToFit;
  y = self.view_enableLog.$maxY + 5;

  $(self.view_mcpServerEnabled).x(115).toRight(insets.right).y(y).heightToFit;
  y = self.view_mcpServerEnabled.$maxY + 5;

  [self.mcpPortLabel sizeToFit];
  $(self.mcpPortLabel)
      .x(134)
      .y(y)
      .height([self.mcpPortLabel fittingSize].height + 5);

  $(self.mcpPortField)
      .x(self.mcpPortLabel.$maxX + 5)
      .y(y - 2)
      .width(80)
      .height(22);
  y = self.mcpPortField.$maxY + 12;

  $(self.aiAccessModeControl).x(134).y(y).width(260).height(28);
  $(self.aiCommandCopyButton)
      .x(self.aiAccessModeControl.$maxX + 8)
      .y(y)
      .width(32)
      .height(28);
  y = self.aiAccessModeControl.$maxY + 10;

  self.mcpConfigLabel.preferredMaxLayoutWidth =
      self.view.bounds.size.width - 134 - insets.right;
  [self.mcpConfigLabel sizeToFit];
  $(self.mcpConfigLabel)
      .x(134)
      .y(y)
      .toRight(insets.right)
      .height([self.mcpConfigLabel fittingSize].height);
  y = self.mcpConfigLabel.$maxY + 5;

  $(self.resetButton).width(120).bottom(insets.bottom).right(insets.right);
  //    $(self.debugButton).bottom(insets.bottom).maxX(self.resetButton.$x -
  //    15);
}

- (void)_handleResetButton {
  LKPreferenceManager *manager = [LKPreferenceManager mainManager];
  manager.appearanceType = LookinPreferredAppeanranceTypeSystem;
  manager.enableReport = YES;
  manager.rgbaFormat = YES;
  manager.doubleClickBehavior = LookinDoubleClickBehaviorCollapse;
  manager.imageContrastLevel = 0;
  [self renderFromPreferenceManager];

#if DEBUG
  [[LKMessageManager sharedInstance] reset];
  [[LKPreferenceManager mainManager] reset];
  [[NSUserDefaults standardUserDefaults]
      removeObjectForKey:@"IgnoreFastModeTips"];
#endif
}

- (void)_handleDebugButton {
  NSString *appDomain = [[NSBundle mainBundle] bundleIdentifier];
  [[NSUserDefaults standardUserDefaults]
      removePersistentDomainForName:appDomain];
  [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
