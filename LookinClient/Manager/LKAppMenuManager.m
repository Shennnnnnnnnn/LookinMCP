//
//  LKAppMenuManager.m
//  Lookin
//
//  Created by Li Kai on 2019/3/20.
//  https://lookin.work
//

#import "LKAppMenuManager.h"
#import "LKLaunchViewController.h"
#import "LKLaunchWindowController.h"
#import "LKMCPBridge.h"
#import "LKNavigationManager.h"
#import "LKPreferenceManager.h"
#import "LKPreviewController.h"
#import "LKStaticHierarchyDataSource.h"
#import "LKStaticViewController.h"
#import "LKStaticWindowController.h"
#import "LKWindowController.h"
#import <Sparkle/Sparkle.h>
#include <mach-o/dyld.h>
@import AppCenter;
@import AppCenterAnalytics;

static NSUInteger const kTag_About = 11;
static NSUInteger const kTag_Preferences = 12;
static NSUInteger const kTag_CheckUpdates = 13;

static NSUInteger const kTag_Reload = 21;
static NSUInteger const kTag_Dimension = 22;
static NSUInteger const kTag_ZoomIn = 23;
static NSUInteger const kTag_ZoomOut = 24;
static NSUInteger const kTag_DecreaseInterspace = 25;
static NSUInteger const kTag_IncreaseInterspace = 26;
static NSUInteger const kTag_Expansion = 27;
static NSUInteger const kTag_Filter = 28;
static NSUInteger const kTag_OpenInNewWindow = 31;
static NSUInteger const kTag_Export = 32;

static NSUInteger const kTag_CocoaPods = 51;
static NSUInteger const kTag_ShowWebsite = 52;
static NSUInteger const kTag_ShowConfig = 53;
static NSUInteger const kTag_ShowLookiniOS = 54;

static NSUInteger const kTag_GitHub = 57;
static NSUInteger const kTag_LookinClientGitHub = 58;
static NSUInteger const kTag_LookinServerGitHub = 59;

static NSUInteger const kTag_ReportIssues = 60;
static NSUInteger const kTag_LookinClientGitHubIssues = 62;
static NSUInteger const kTag_LookinServerGitHubIssues = 63;
static NSUInteger const kTag_Weibo = 64;

static NSUInteger const kTag_CopyPod = 66;
static NSUInteger const kTag_CopySPM = 67;
static NSUInteger const kTag_MoreIntegrationGuide = 68;
static NSUInteger const kTag_Jobs = 69;
static NSUInteger const kTag_DocumentCollection = 70;
static NSUInteger const kTag_CustomInformation = 71;
static NSUInteger const kTag_Acknowledgements = 72;

// MCP 相关
static NSUInteger const kTag_MCP = 80;
static NSUInteger const kTag_MCPToggleServer = 81;
static NSUInteger const kTag_MCPExportHierarchy = 82;
static NSUInteger const kTag_MCPServerStatus = 83;
static NSUInteger const kTag_MCPExportImages = 84;

@interface LKAppMenuManager ()

@property(nonatomic, copy)
    NSDictionary<NSNumber *, NSString *> *delegatingTagToSelMap;

@end

@implementation LKAppMenuManager

+ (instancetype)sharedInstance {
  static dispatch_once_t onceToken;
  static LKAppMenuManager *instance = nil;
  dispatch_once(&onceToken, ^{
    instance = [[super allocWithZone:NULL] init];
  });
  return instance;
}

+ (id)allocWithZone:(struct _NSZone *)zone {
  return [self sharedInstance];
}

- (void)setup {
  self.delegatingTagToSelMap = @{
    @(kTag_Reload) :
        NSStringFromSelector(@selector(appMenuManagerDidSelectReload)),
    @(kTag_Dimension) :
        NSStringFromSelector(@selector(appMenuManagerDidSelectDimension)),
    @(kTag_ZoomIn) :
        NSStringFromSelector(@selector(appMenuManagerDidSelectZoomIn)),
    @(kTag_ZoomOut) :
        NSStringFromSelector(@selector(appMenuManagerDidSelectZoomOut)),
    @(kTag_DecreaseInterspace) : NSStringFromSelector(
        @selector(appMenuManagerDidSelectDecreaseInterspace)),
    @(kTag_IncreaseInterspace) : NSStringFromSelector(
        @selector(appMenuManagerDidSelectIncreaseInterspace)),
    @(kTag_Expansion) :
        NSStringFromSelector(@selector(appMenuManagerDidSelectExpansionIndex:)),
    @(kTag_Export) :
        NSStringFromSelector(@selector(appMenuManagerDidSelectExport)),
    @(kTag_OpenInNewWindow) :
        NSStringFromSelector(@selector(appMenuManagerDidSelectOpenInNewWindow)),
    @(kTag_Filter) :
        NSStringFromSelector(@selector(appMenuManagerDidSelectFilter)),
  };

  NSMenu *menu = [NSApp mainMenu];

  // Lookin
  NSMenu *menu_lookin = [menu itemAtIndex:0].submenu;
  menu_lookin.autoenablesItems = NO;
  menu_lookin.delegate = self;

  NSMenuItem *menuItem_about = [menu_lookin itemWithTag:kTag_About];
  menuItem_about.target = self;
  menuItem_about.action = @selector(_handleAbout);

  // Lookin - 偏好设置
  NSMenuItem *menuItem_preferences = [menu_lookin itemWithTag:kTag_Preferences];
  menuItem_preferences.target = self;
  menuItem_preferences.action = @selector(_handlePreferences);

  NSMenuItem *menuItem_checkUpdates =
      [menu_lookin itemWithTag:kTag_CheckUpdates];
  menuItem_checkUpdates.target = self;
  menuItem_checkUpdates.action = @selector(_handleCheckUpdates);

  // 文件
  NSMenu *menu_file = [menu itemAtIndex:1].submenu;
  menu_file.autoenablesItems = NO;
  menu_file.delegate = self;

  // 视图
  NSMenu *menu_view = [menu itemAtIndex:3].submenu;
  menu_view.autoenablesItems = NO;
  menu_view.delegate = self;

  // 帮助
  NSMenu *menu_help = [menu itemAtIndex:5].submenu;
  menu_help.autoenablesItems = YES;
  menu_help.delegate = self;

  // 帮助 - CocoaPods
  NSMenuItem *menuItem_cocoaPods = [menu_help itemWithTag:kTag_CocoaPods];
  menuItem_cocoaPods.target = self;
  menuItem_cocoaPods.action = @selector(_handleShowCocoaPods);

  // 帮助 - 官方网站
  NSMenuItem *menuItem_showWebsite = [menu_help itemWithTag:kTag_ShowWebsite];
  menuItem_showWebsite.target = self;
  menuItem_showWebsite.action = @selector(_handleShowWebsite);

  // 帮助 - 创建配置文件
  NSMenuItem *menuItem_showConfig = [menu_help itemWithTag:kTag_ShowConfig];
  menuItem_showConfig.target = self;
  menuItem_showConfig.action = @selector(_handleShowConfig);

  // 帮助 - 在 iOS 上使用 Lookin
  NSMenuItem *menuItem_showLookiniOS =
      [menu_help itemWithTag:kTag_ShowLookiniOS];
  menuItem_showLookiniOS.target = self;
  menuItem_showLookiniOS.action = @selector(_handleShowLookiniOS);

  NSMenu *sourceCodeMenu = [menu_help itemWithTag:kTag_GitHub].submenu;
  {
    NSMenuItem *item = [sourceCodeMenu itemWithTag:kTag_LookinClientGitHub];
    item.target = self;
    item.action = @selector(_handleShowLookinClientGithub);
  }

  {
    NSMenuItem *item = [sourceCodeMenu itemWithTag:kTag_LookinServerGitHub];
    item.target = self;
    item.action = @selector(_handleShowLookinServerGithub);
  }

  NSMenu *issuesMenu = [menu_help itemWithTag:kTag_ReportIssues].submenu;
  {
    NSMenuItem *item = [issuesMenu itemWithTag:kTag_LookinClientGitHubIssues];
    item.target = self;
    item.action = @selector(_handleClientIssues);
  }
  {
    NSMenuItem *item = [issuesMenu itemWithTag:kTag_LookinServerGitHubIssues];
    item.target = self;
    item.action = @selector(_handleServerIssues);
  }
  {
    NSMenuItem *item = [issuesMenu itemWithTag:kTag_Weibo];
    item.target = self;
    item.action = @selector(_handleWeibo);
  }

  {
    NSMenuItem *item = [menu_help itemWithTag:kTag_CopyPod];
    item.target = self;
    item.action = @selector(_handleCopyPod);
  }
  {
    NSMenuItem *item = [menu_help itemWithTag:kTag_CopySPM];
    item.target = self;
    item.action = @selector(_handleCopySPM);
  }
  {
    NSMenuItem *item = [menu_help itemWithTag:kTag_MoreIntegrationGuide];
    item.target = self;
    item.action = @selector(_handleOpenMoreIntegrationGuide);
  }
  {
    NSMenuItem *item = [menu_help itemWithTag:kTag_Jobs];
    item.target = self;
    item.action = @selector(_handleJobs);
  }
  {
    NSMenuItem *item = [menu_help itemWithTag:kTag_DocumentCollection];
    item.target = self;
    item.action = @selector(_handleDocumentCollection);
  }
  {
    NSMenuItem *item = [menu_help itemWithTag:kTag_CustomInformation];
    item.target = self;
    item.action = @selector(_handleCustomInformation);
  }
  {
    NSMenuItem *item = [menu_help itemWithTag:kTag_Acknowledgements];
    item.target = self;
    item.action = @selector(_handleAcknowledgements);
  }

  // MCP 菜单
  [self setupMCPMenu:menu_help];

  NSArray *itemArray =
      [menu_file.itemArray arrayByAddingObjectsFromArray:menu_view.itemArray];
  [itemArray enumerateObjectsUsingBlock:^(NSMenuItem *_Nonnull obj,
                                          NSUInteger idx, BOOL *_Nonnull stop) {
    NSString *selString = self.delegatingTagToSelMap[@(obj.tag)];
    if (selString) {
      if (obj.hasSubmenu) {
        if (obj.tag == kTag_Expansion) {
          // 视图 - 深度
          [obj.submenu.itemArray enumerateObjectsUsingBlock:^(
                                     NSMenuItem *_Nonnull expansionSubItem,
                                     NSUInteger idx, BOOL *_Nonnull stop) {
            expansionSubItem.target = self;
            expansionSubItem.representedObject = @(idx);
            expansionSubItem.action = @selector(_handleExpansion:);
          }];
        }
      } else {
        obj.target = self;
        obj.action = @selector(_handleDelegateItem:);
      }
    }
  }];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
  LKWindowController *wc =
      [LKNavigationManager sharedInstance].currentKeyWindowController;

  [menu.itemArray
      enumerateObjectsUsingBlock:^(NSMenuItem *_Nonnull obj, NSUInteger idx,
                                   BOOL *_Nonnull stop) {
        NSString *selString = self.delegatingTagToSelMap[@(obj.tag)];
        if (selString) {
          SEL delegateSel = NSSelectorFromString(selString);
          obj.enabled = [wc respondsToSelector:delegateSel];
        } else {
          obj.enabled = YES;
        }
      }];
}

- (void)_handlePreferences {
  [[LKNavigationManager sharedInstance] showPreference];
}

- (void)_handleDelegateItem:(NSMenuItem *)item {
  NSString *selString = self.delegatingTagToSelMap[@(item.tag)];
  SEL sel = NSSelectorFromString(selString);
  if (!sel) {
    NSAssert(NO, @"");
    return;
  }
  LKWindowController *wc =
      [LKNavigationManager sharedInstance].currentKeyWindowController;
  if (![wc respondsToSelector:sel]) {
    NSAssert(NO, @"");
    return;
  }
  NSInvocation *invocation = [NSInvocation
      invocationWithMethodSignature:[wc methodSignatureForSelector:sel]];
  [invocation setTarget:wc];
  [invocation setSelector:sel];
  [invocation invoke];
}

- (void)_handleExpansion:(NSMenuItem *)item {
  NSNumber *idxNum = item.representedObject;
  if (idxNum == nil) {
    NSAssert(NO, @"");
    return;
  }
  NSUInteger index = idxNum.unsignedIntegerValue;

  LKWindowController *wc =
      [LKNavigationManager sharedInstance].currentKeyWindowController;
  if (![wc respondsToSelector:@selector
           (appMenuManagerDidSelectExpansionIndex:)]) {
    NSAssert(NO, @"");
    return;
  }
  [wc appMenuManagerDidSelectExpansionIndex:index];

  [MSACAnalytics
          trackEvent:@"Hierarchy Expansion"
      withProperties:@{@"level" : [NSString stringWithFormat:@"%@", idxNum]}];
}

- (void)_handleShowConfig {
  [LKHelper openLookinWebsiteWithPath:@"faq/config-file/"];
}

- (void)_handleShowLookiniOS {
  [LKHelper openLookinWebsiteWithPath:@"faq/lookin-ios/"];
}

- (void)_handleShowLookinClientGithub {
  [[NSWorkspace sharedWorkspace]
      openURL:[NSURL URLWithString:@"https://github.com/hughkli/Lookin"]];
}

- (void)_handleShowLookinServerGithub {
  [[NSWorkspace sharedWorkspace]
      openURL:[NSURL URLWithString:@"https://github.com/QMUI/LookinServer"]];
}

- (void)_handleClientIssues {
  [[NSWorkspace sharedWorkspace]
      openURL:[NSURL
                  URLWithString:@"https://github.com/hughkli/Lookin/issues"]];
}

- (void)_handleServerIssues {
  [[NSWorkspace sharedWorkspace]
      openURL:
          [NSURL URLWithString:@"https://github.com/QMUI/LookinServer/issues"]];
}

- (void)_handleWeibo {
  [[NSWorkspace sharedWorkspace]
      openURL:[NSURL URLWithString:@"https://weibo.com/234885306"]];
}

- (void)_handleShowWebsite {
  [LKHelper openLookinOfficialWebsite];
}

- (void)_handleCopyPod {
  NSString *stringToCopy = @"pod 'LookinServer', :configurations => ['Debug']";

  NSPasteboard *paste = [NSPasteboard generalPasteboard];
  [paste clearContents];
  [paste writeObjects:@[ stringToCopy ]];
}

- (void)_handleCopySPM {
  NSString *stringToCopy = @"https://github.com/QMUI/LookinServer/";

  NSPasteboard *paste = [NSPasteboard generalPasteboard];
  [paste clearContents];
  [paste writeObjects:@[ stringToCopy ]];
}

- (void)_handleOpenMoreIntegrationGuide {
  [[NSWorkspace sharedWorkspace]
      openURL:[NSURL URLWithString:@"https://github.com/QMUI/LookinServer/blob/"
                                   @"master/README.md"]];
}

- (void)_handleJobs {
  [[NSWorkspace sharedWorkspace]
      openURL:[NSURL URLWithString:@"https://bytedance.feishu.cn/docx/"
                                   @"SAcgdoQuAouyXAxAqy8cmrT2n4b"]];
}

- (void)_handleCheckUpdates {
  [[SUUpdater sharedUpdater] checkForUpdates:self];
}

- (void)_handleShowCocoaPods {
  [LKHelper openLookinWebsiteWithPath:@"faq/integration-guide/"];
}

- (void)_handleAbout {
  [[LKNavigationManager sharedInstance] showAbout];
}

- (void)_handleDocumentCollection {
  [[NSWorkspace sharedWorkspace]
      openURL:[NSURL URLWithString:@"https://bytedance.larkoffice.com/docx/"
                                   @"Yvv1d57XQoe5l0xZ0ZRc0ILfnWb"]];
}

- (void)_handleCustomInformation {
  [[NSWorkspace sharedWorkspace]
      openURL:[NSURL URLWithString:@"https://bytedance.larkoffice.com/docx/"
                                   @"TRridRXeUoErMTxs94bcnGchnlb"]];
}

- (void)_handleAcknowledgements {
  [[NSWorkspace sharedWorkspace]
      openURL:[NSURL URLWithString:@"https://qxh1ndiez2w.feishu.cn/docx/"
                                   @"YIFjdE4gIolp3hxn1tGckiBxnWf"]];
}

#pragma mark - MCP Menu

- (void)setupMCPMenu:(NSMenu *)helpMenu {
  // 在帮助菜单中添加 MCP 相关项
  [helpMenu addItem:[NSMenuItem separatorItem]];

  // MCP 子菜单
  NSMenu *mcpMenu = [[NSMenu alloc] initWithTitle:@"MCP"];

  // 切换服务器状态
  NSMenuItem *toggleServerItem =
      [[NSMenuItem alloc] initWithTitle:@"启动 MCP 服务器"
                                 action:@selector(_handleMCPToggleServer:)
                          keyEquivalent:@""];
  toggleServerItem.target = self;
  toggleServerItem.tag = kTag_MCPToggleServer;
  [mcpMenu addItem:toggleServerItem];

  // 服务器状态
  NSMenuItem *statusItem =
      [[NSMenuItem alloc] initWithTitle:@"服务器状态: 未启动"
                                 action:nil
                          keyEquivalent:@""];
  statusItem.tag = kTag_MCPServerStatus;
  statusItem.enabled = NO;
  [mcpMenu addItem:statusItem];

  [mcpMenu addItem:[NSMenuItem separatorItem]];

  // 导出视图层级到剪贴板
  NSMenuItem *exportItem =
      [[NSMenuItem alloc] initWithTitle:@"导出视图层级到剪贴板"
                                 action:@selector(_handleMCPExportHierarchy:)
                          keyEquivalent:@""];
  exportItem.target = self;
  exportItem.tag = kTag_MCPExportHierarchy;
  [mcpMenu addItem:exportItem];

  NSMenuItem *exportImagesItem =
      [[NSMenuItem alloc] initWithTitle:@"批量导出当前界面图片…"
                                 action:@selector(_handleMCPExportImages:)
                          keyEquivalent:@""];
  exportImagesItem.target = self;
  exportImagesItem.tag = kTag_MCPExportImages;
  [mcpMenu addItem:exportImagesItem];

  // 添加到帮助菜单
  NSMenuItem *mcpMenuItem = [[NSMenuItem alloc] initWithTitle:@"MCP"
                                                       action:nil
                                                keyEquivalent:@""];
  mcpMenuItem.tag = kTag_MCP;
  [mcpMenuItem setSubmenu:mcpMenu];
  [helpMenu addItem:mcpMenuItem];

  // 更新服务器状态
  [self updateMCPServerStatus];
}

- (void)updateMCPServerStatus {
  NSMenu *mainMenu = [NSApp mainMenu];
  NSMenu *helpMenu = [mainMenu itemAtIndex:5].submenu;
  NSMenuItem *mcpMenuItem = [helpMenu itemWithTag:kTag_MCP];
  NSMenu *mcpMenu = mcpMenuItem.submenu;

  NSMenuItem *toggleItem = [mcpMenu itemWithTag:kTag_MCPToggleServer];
  NSMenuItem *statusItem = [mcpMenu itemWithTag:kTag_MCPServerStatus];
}

- (void)_handleMCPToggleServer:(NSMenuItem *)sender {
  LKMCPBridge *bridge = [LKMCPBridge sharedInstance];

  [self updateMCPServerStatus];
}

- (void)_handleMCPExportHierarchy:(NSMenuItem *)sender {
  NSString *hierarchyJSON =
      [[LKMCPBridge sharedInstance] exportHierarchyWithMaxDepth:-1
                                                    filterClass:nil
                                                      elementID:nil];

  if (hierarchyJSON) {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:hierarchyJSON forType:NSPasteboardTypeString];

    NSLog(@"视图层级已复制到剪贴板");

    // 显示通知
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"导出成功";
    alert.informativeText = @"视图层级数据已复制到剪贴板";
    alert.alertStyle = NSAlertStyleInformational;
    [alert addButtonWithTitle:@"确定"];
    [alert runModal];
  } else {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"导出失败";
    alert.informativeText = @"没有可用的视图层级数据，请先连接到应用并刷新";
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"确定"];
    [alert runModal];
  }
}

- (void)_handleMCPExportImages:(NSMenuItem *)sender {
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  panel.canChooseFiles = NO;
  panel.canChooseDirectories = YES;
  panel.canCreateDirectories = YES;
  panel.allowsMultipleSelection = NO;
  panel.prompt = @"导出";
  panel.message = @"选择用于保存当前界面全部 UIImageView 图片的文件夹";

  void (^panelCompletion)(NSModalResponse) = ^(NSModalResponse result) {
    if (result != NSModalResponseOK || !panel.URL) {
      return;
    }
    NSString *directory = panel.URL.path;
    [[LKMCPBridge sharedInstance]
        exportAllImagesToDirectory:directory
                        completion:^(NSString *jsonString) {
                          NSData *data =
                              [jsonString dataUsingEncoding:NSUTF8StringEncoding];
                          NSDictionary *payload = data
                                                      ? [NSJSONSerialization
                                                            JSONObjectWithData:data
                                                                       options:0
                                                                         error:nil]
                                                      : nil;
                          dispatch_async(dispatch_get_main_queue(), ^{
                            NSString *status = payload[@"status"];
                            BOOL success = [status isEqualToString:@"success"] ||
                                           [status isEqualToString:@"partial_success"];
                            NSAlert *alert = [[NSAlert alloc] init];
                            alert.messageText = success ? @"图片导出完成" : @"图片导出失败";
                            alert.informativeText = payload[@"message"] ?: @"未知错误";
                            alert.alertStyle = success ? NSAlertStyleInformational
                                                       : NSAlertStyleWarning;
                            [alert addButtonWithTitle:@"确定"];
                            if (success) {
                              [alert addButtonWithTitle:@"在 Finder 中显示"];
                            }
                            NSModalResponse response = [alert runModal];
                            if (success && response == NSAlertSecondButtonReturn) {
                              [[NSWorkspace sharedWorkspace]
                                  activateFileViewerSelectingURLs:@[
                                    [NSURL fileURLWithPath:directory]
                                  ]];
                            }
                          });
                        }];
  };

  if (NSApp.keyWindow) {
    [panel beginSheetModalForWindow:NSApp.keyWindow
                 completionHandler:panelCompletion];
  } else {
    [panel beginWithCompletionHandler:panelCompletion];
  }
}

@end
