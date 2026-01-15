//
//  LKMCPBridge.m
//  Lookin
//
//  Created for MCP Integration
//

#import "LKMCPBridge.h"

// 定义该宏以暴露 LookinDisplayItem.h 中的 viewObject 等属性
#ifndef SHOULD_COMPILE_LOOKIN_SERVER
#define SHOULD_COMPILE_LOOKIN_SERVER 1
#endif
#import "LKAppsManager.h"
#import "LKInspectableApp.h"
#import "LKStaticHierarchyDataSource.h"
#import "LookinAttribute.h"
#import "LookinAttributeModification.h"
#import "LookinAttributesGroup.h"
#import "LookinAttributesSection.h"
#import "LookinDisplayItem+LookinClient.h"
#import "LookinDisplayItem.h"
#import "LookinDisplayItemDetail.h"
#import "LookinHierarchyInfo.h"
#import "LookinObject+LookinClient.h"
#import "LookinObject.h"

@interface LKMCPBridge ()

@end

@implementation LKMCPBridge

+ (instancetype)sharedInstance {
  static LKMCPBridge *instance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[LKMCPBridge alloc] init];
  });
  return instance;
}

- (instancetype)init {
  return [super init];
}

#pragma mark - Data Export

- (NSString *)exportHierarchyWithMaxDepth:(NSInteger)maxDepth
                              filterClass:(nullable NSString *)filterClass {
  LKStaticHierarchyDataSource *dataSource =
      [LKStaticHierarchyDataSource sharedInstance];
  LookinHierarchyInfo *hierarchyInfo = dataSource.rawHierarchyInfo;

  if (!hierarchyInfo) {
    return [self errorJSON:@"没有可用的视图层级数据"];
  }

  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  result[@"status"] = @"success";
  result[@"message"] = @"视图层级获取成功";

  // 导出根元素 - displayItems 是数组
  if (hierarchyInfo.displayItems && hierarchyInfo.displayItems.count > 0) {
    NSMutableArray *hierarchyArray = [NSMutableArray array];
    for (LookinDisplayItem *item in hierarchyInfo.displayItems) {
      NSDictionary *itemDict = [self exportDisplayItem:item
                                              maxDepth:maxDepth
                                          currentDepth:0
                                           filterClass:filterClass];
      if (itemDict) {
        [hierarchyArray addObject:itemDict];
      }
    }
    result[@"hierarchy"] = hierarchyArray;
  }

  return [self jsonStringFromDictionary:result];
}

- (NSDictionary *)exportDisplayItem:(LookinDisplayItem *)item
                           maxDepth:(NSInteger)maxDepth
                       currentDepth:(NSInteger)currentDepth
                        filterClass:(nullable NSString *)filterClass {
  if (!item) {
    return nil;
  }

  // 检查深度限制
  if (maxDepth >= 0 && currentDepth > maxDepth) {
    return nil;
  }

  NSMutableDictionary *itemDict = [NSMutableDictionary dictionary];

  // 提取真实的类名
  NSString *trueClassName =
      item.viewObject.lk_simpleDemangledClassName
          ?: (item.layerObject.lk_simpleDemangledClassName ?: item.className);

  // 简单的类名过滤
  if (filterClass && filterClass.length > 0) {
    if (![trueClassName localizedCaseInsensitiveContainsString:filterClass]) {
      return nil;
    }
  }

  itemDict[@"className"] = trueClassName ?: @"";

  // 基本信息 - 优先使用 viewObject 的 oid 作为主 oid
  NSNumber *oidValue = nil;
  if (item.viewObject) {
    oidValue = @(item.viewObject.oid);
    itemDict[@"viewOID"] = [NSString stringWithFormat:@"%@", oidValue];
  }
  if (item.layerObject) {
    if (!oidValue) {
      oidValue = @(item.layerObject.oid);
    }
    itemDict[@"layerOID"] =
        [NSString stringWithFormat:@"%lu", item.layerObject.oid];
  }

  itemDict[@"oid"] =
      oidValue ? [NSString stringWithFormat:@"%@", oidValue] : @"";

  // 使用 title 方法获取显示标题
  NSString *title = [item title];
  if (title) {
    itemDict[@"title"] = title;
  }

  // 尝试提取文本内容
  NSString *textContent = [self getTextContentFromItem:item];
  if (textContent && textContent.length > 0) {
    itemDict[@"text"] = textContent;
  }

  // Frame 信息
  if (!CGRectIsNull(item.frame)) {
    itemDict[@"frame"] = @{
      @"x" : @(item.frame.origin.x),
      @"y" : @(item.frame.origin.y),
      @"width" : @(item.frame.size.width),
      @"height" : @(item.frame.size.height)
    };
  }

  // 可见性
  itemDict[@"isHidden"] = @(item.isHidden);
  itemDict[@"alpha"] = @(item.alpha);

  // 层级信息
  itemDict[@"depth"] = @(currentDepth);

  // 导出子元素
  if (item.subitems && item.subitems.count > 0) {
    NSMutableArray *children = [NSMutableArray array];
    for (LookinDisplayItem *subitem in item.subitems) {
      NSDictionary *childDict = [self exportDisplayItem:subitem
                                               maxDepth:maxDepth
                                           currentDepth:currentDepth + 1
                                            filterClass:filterClass];
      if (childDict) {
        [children addObject:childDict];
      }
    }
    if (children.count > 0) {
      itemDict[@"children"] = children;
    }
  }

  return itemDict;
}

- (NSString *)exportElementInfoWithOID:(NSString *)oid {
  LKStaticHierarchyDataSource *dataSource =
      [LKStaticHierarchyDataSource sharedInstance];
  LookinDisplayItem *item = [self findDisplayItemWithOID:oid];

  if (!item) {
    return [self
        errorJSON:[NSString stringWithFormat:@"未找到 OID 为 %@ 的元素", oid]];
  }

  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  result[@"status"] = @"success";
  result[@"element_id"] = oid;

  NSMutableDictionary *details = [NSMutableDictionary dictionary];

  // 基本信息
  details[@"className"] = item.className ?: @"";
  details[@"hasViewObject"] = @(item.viewObject != nil);
  NSString *title = [item title];
  if (title) {
    details[@"title"] = title;
  }

  NSString *textContent = [self getTextContentFromItem:item];
  if (textContent) {
    details[@"text"] = textContent;
  } else {
    details[@"debug_text_extraction"] = @"Failed to extract text";
  }

  // Frame 和 Bounds
  if (!CGRectIsNull(item.frame)) {
    details[@"frame"] = @{
      @"x" : @(item.frame.origin.x),
      @"y" : @(item.frame.origin.y),
      @"width" : @(item.frame.size.width),
      @"height" : @(item.frame.size.height)
    };
  }

  if (!CGRectIsNull(item.bounds)) {
    details[@"bounds"] = @{
      @"x" : @(item.bounds.origin.x),
      @"y" : @(item.bounds.origin.y),
      @"width" : @(item.bounds.size.width),
      @"height" : @(item.bounds.size.height)
    };
  }

  // 可见性和交互
  details[@"isHidden"] = @(item.isHidden);
  details[@"alpha"] = @(item.alpha);

  // 背景色
  if (item.backgroundColor) {
    details[@"backgroundColor"] = [self serializeColor:item.backgroundColor];
  }

  // 层级关系
  if (item.superItem) {
    NSNumber *superOid = nil;
    if (item.superItem.layerObject) {
      superOid = @(item.superItem.layerObject.oid);
    } else if (item.superItem.viewObject) {
      superOid = @(item.superItem.viewObject.oid);
    }
    if (superOid) {
      details[@"superItemOID"] = [NSString stringWithFormat:@"%@", superOid];
    }
  }

  if (item.subitems && item.subitems.count > 0) {
    NSMutableArray *subitemOIDs = [NSMutableArray array];
    for (LookinDisplayItem *subitem in item.subitems) {
      NSNumber *subOid = nil;
      if (subitem.layerObject) {
        subOid = @(subitem.layerObject.oid);
      } else if (subitem.viewObject) {
        subOid = @(subitem.viewObject.oid);
      }
      if (subOid) {
        [subitemOIDs addObject:[NSString stringWithFormat:@"%@", subOid]];
      }
    }
    details[@"subitemOIDs"] = subitemOIDs;
  }

  // 获取详细属性（文案、字体、颜色、圆角等）
  if (item.attributesGroupList && item.attributesGroupList.count > 0) {
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];

    for (LookinAttributesGroup *group in item.attributesGroupList) {
      if (!group.attrSections || group.attrSections.count == 0) {
        continue;
      }

      for (LookinAttributesSection *section in group.attrSections) {
        if (!section.attributes || section.attributes.count == 0) {
          continue;
        }

        for (LookinAttribute *attr in section.attributes) {
          NSString *key = attr.identifier ?: attr.displayTitle;
          if (!key || !attr.value) {
            continue;
          }

          // 序列化属性值
          id serializedValue = [self serializeAttributeValue:attr];
          if (serializedValue) {
            attributes[key] = serializedValue;
          }
        }
      }
    }

    if (attributes.count > 0) {
      details[@"attributes"] = attributes;
    }
  }

  result[@"details"] = details;

  return [self jsonStringFromDictionary:result];
}

- (NSString *)calculateRelativePositionBetween:(NSString *)oid1
                                           and:(NSString *)oid2 {
  LookinDisplayItem *item1 = [self findDisplayItemWithOID:oid1];
  LookinDisplayItem *item2 = [self findDisplayItemWithOID:oid2];

  if (!item1 || !item2) {
    return [self errorJSON:@"未找到指定的元素"];
  }

  CGRect frame1 = item1.frame;
  CGRect frame2 = item2.frame;

  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  result[@"status"] = @"success";
  result[@"element_1"] = oid1;
  result[@"element_2"] = oid2;

  NSMutableDictionary *relationship = [NSMutableDictionary dictionary];

  // 水平关系
  if (CGRectGetMaxX(frame1) <= CGRectGetMinX(frame2)) {
    relationship[@"horizontal"] = @"element_1 在 element_2 左侧";
    relationship[@"horizontal_distance"] =
        @(CGRectGetMinX(frame2) - CGRectGetMaxX(frame1));
  } else if (CGRectGetMinX(frame1) >= CGRectGetMaxX(frame2)) {
    relationship[@"horizontal"] = @"element_1 在 element_2 右侧";
    relationship[@"horizontal_distance"] =
        @(CGRectGetMinX(frame1) - CGRectGetMaxX(frame2));
  } else {
    relationship[@"horizontal"] = @"element_1 与 element_2 水平重叠";
    relationship[@"horizontal_distance"] = @0;
  }

  // 垂直关系
  if (CGRectGetMaxY(frame1) <= CGRectGetMinY(frame2)) {
    relationship[@"vertical"] = @"element_1 在 element_2 上方";
    relationship[@"vertical_distance"] =
        @(CGRectGetMinY(frame2) - CGRectGetMaxY(frame1));
  } else if (CGRectGetMinY(frame1) >= CGRectGetMaxY(frame2)) {
    relationship[@"vertical"] = @"element_1 在 element_2 下方";
    relationship[@"vertical_distance"] =
        @(CGRectGetMinY(frame1) - CGRectGetMaxY(frame2));
  } else {
    relationship[@"vertical"] = @"element_1 与 element_2 垂直重叠";
    relationship[@"vertical_distance"] = @0;
  }

  // 是否重叠
  BOOL overlap = CGRectIntersectsRect(frame1, frame2);
  relationship[@"overlap"] = @(overlap);

  if (overlap) {
    CGRect intersection = CGRectIntersection(frame1, frame2);
    relationship[@"intersection"] = @{
      @"x" : @(intersection.origin.x),
      @"y" : @(intersection.origin.y),
      @"width" : @(intersection.size.width),
      @"height" : @(intersection.size.height)
    };
  }

  result[@"relationship"] = relationship;

  return [self jsonStringFromDictionary:result];
}

- (NSString *)searchElementsWithQuery:(NSString *)query
                                 type:(NSString *)searchType {
  LKStaticHierarchyDataSource *dataSource =
      [LKStaticHierarchyDataSource sharedInstance];
  LookinHierarchyInfo *hierarchyInfo = dataSource.rawHierarchyInfo;

  if (!hierarchyInfo || !hierarchyInfo.displayItems ||
      hierarchyInfo.displayItems.count == 0) {
    return [self errorJSON:@"没有可用的视图层级数据"];
  }

  NSMutableArray *results = [NSMutableArray array];
  for (LookinDisplayItem *item in hierarchyInfo.displayItems) {
    [self searchInDisplayItem:item
                        query:query
                   searchType:searchType
                      results:results];
  }

  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  result[@"status"] = @"success";
  result[@"query"] = query;
  result[@"search_type"] = searchType;
  result[@"count"] = @(results.count);
  result[@"results"] = results;

  return [self jsonStringFromDictionary:result];
}

- (void)searchInDisplayItem:(LookinDisplayItem *)item
                      query:(NSString *)query
                 searchType:(NSString *)searchType
                    results:(NSMutableArray *)results {
  if (!item) {
    return;
  }

  BOOL matched = NO;

  // Resolve true class name
  NSString *trueClassName =
      item.viewObject.lk_simpleDemangledClassName
          ?: (item.layerObject.lk_simpleDemangledClassName ?: item.className);

  // 1. Class Name Search (Case Insensitive)
  if ([searchType isEqualToString:@"all"] ||
      [searchType isEqualToString:@"class"]) {
    if (trueClassName && [trueClassName rangeOfString:query
                                              options:NSCaseInsensitiveSearch]
                                 .location != NSNotFound) {
      matched = YES;
    }
  }

  // 2. Text Search (Case Insensitive)
  if (!matched && ([searchType isEqualToString:@"all"] ||
                   [searchType isEqualToString:@"text"])) {
    NSString *title = [item title];
    if (title &&
        [title rangeOfString:query options:NSCaseInsensitiveSearch].location !=
            NSNotFound) {
      matched = YES;
    }
    if (!matched) {
      NSString *text = [self getTextContentFromItem:item];
      if (text &&
          [text rangeOfString:query options:NSCaseInsensitiveSearch].location !=
              NSNotFound) {
        matched = YES;
      }
    }
  }

  // 3. Identifier / OID Search
  if (!matched && ([searchType isEqualToString:@"all"] ||
                   [searchType isEqualToString:@"identifier"])) {
    NSNumber *oidValue = nil;
    if (item.layerObject) {
      oidValue = @(item.layerObject.oid);
    } else if (item.viewObject) {
      oidValue = @(item.viewObject.oid);
    }
    if (oidValue &&
        [[NSString stringWithFormat:@"%@", oidValue] containsString:query]) {
      matched = YES;
    }
  }

  // 4. Size Search
  if (!matched && ([searchType isEqualToString:@"all"] ||
                   [searchType isEqualToString:@"size"])) {
    // Parse query for width x height
    // formats: "100x200", "100.0 x 200.0", "100, 200"

    // Remove spaces
    NSString *cleanQuery =
        [[query stringByReplacingOccurrencesOfString:@" "
                                          withString:@""] lowercaseString];
    NSArray *dims = nil;

    if ([cleanQuery containsString:@"x"]) {
      dims = [cleanQuery componentsSeparatedByString:@"x"];
    } else if ([cleanQuery containsString:@","]) {
      dims = [cleanQuery componentsSeparatedByString:@","];
    }

    if (dims && dims.count == 2) {
      CGFloat targetW = [dims[0] doubleValue];
      CGFloat targetH = [dims[1] doubleValue];

      if (!CGRectIsNull(item.frame)) {
        CGFloat w = item.frame.size.width;
        CGFloat h = item.frame.size.height;

        // Allow small error margin
        if (ABS(w - targetW) < 1.0 && ABS(h - targetH) < 1.0) {
          matched = YES;
        }
      }
    }
  }

  if (matched) {
    NSMutableDictionary *itemInfo = [NSMutableDictionary dictionary];

    NSNumber *oidValue = nil;
    if (item.layerObject) {
      oidValue = @(item.layerObject.oid);
    } else if (item.viewObject) {
      oidValue = @(item.viewObject.oid);
    }
    itemInfo[@"oid"] =
        oidValue ? [NSString stringWithFormat:@"%@", oidValue] : @"";
    itemInfo[@"className"] = trueClassName ?: @"";

    NSString *title = [item title];
    if (title) {
      itemInfo[@"title"] = title;
    }

    NSString *textContent = [self getTextContentFromItem:item];
    if (textContent) {
      itemInfo[@"text"] = textContent;
    }

    if (!CGRectIsNull(item.frame)) {
      itemInfo[@"frame"] = @{
        @"x" : @(item.frame.origin.x),
        @"y" : @(item.frame.origin.y),
        @"width" : @(item.frame.size.width),
        @"height" : @(item.frame.size.height)
      };
    }

    [results addObject:itemInfo];
  }

  // 递归搜索子元素
  for (LookinDisplayItem *subitem in item.subitems) {
    [self searchInDisplayItem:subitem
                        query:query
                   searchType:searchType
                      results:results];
  }
}

- (NSString *)getTextContentFromItem:(LookinDisplayItem *)item {
  __block NSString *textContent = nil;

  // 1. Try to get text from viewObject directly (Must be on Main Thread)
  // Accessing UIKit objects on background thread is unsafe.
  if (item.viewObject) {
    void (^accessBlock)(void) = ^{
      id view = item.viewObject;
      // Priorities: text > currentTitle (Button) > placeholder > stringValue
      NSArray *keys = @[
        @"text", @"currentTitle", @"placeholder", @"stringValue", @"title"
      ];

      for (NSString *key in keys) {
        if ([view respondsToSelector:NSSelectorFromString(key)]) {
          @try {
            id value = [view valueForKey:key];
            if (value && [value isKindOfClass:[NSString class]] &&
                [value length] > 0) {
              textContent = value;
              return;
            }
          } @catch (NSException *exception) {
            // Ignore KVC errors
          }
        }
      }
    };

    if ([NSThread isMainThread]) {
      accessBlock();
    } else {
      dispatch_sync(dispatch_get_main_queue(), accessBlock);
    }
  }

  if (textContent) {
    return textContent;
  }

  // 2. Fallback: Check attributesGroupList (if populated)
  if (!item.attributesGroupList)
    return nil;

  // Check known text property keys (exact matches first, then partial matches)
  NSArray *exactTextKeys = @[
    @"text", @"title", @"string", @"placeholder", @"currentTitle",
    @"stringValue", @"attributedText", @"placeholderText"
  ];

  // Also check partial matches for Lookin-specific identifiers like "lb_t_t"
  NSArray *partialTextKeys =
      @[ @"text", @"title", @"string", @"placeholder", @"lb_t_t" ];

  // First pass: look for exact matches
  for (LookinAttributesGroup *group in item.attributesGroupList) {
    if (!group.attrSections)
      continue;
    for (LookinAttributesSection *section in group.attrSections) {
      if (!section.attributes)
        continue;
      for (LookinAttribute *attr in section.attributes) {
        if (attr.value && [attr.value isKindOfClass:[NSString class]]) {
          // Use identifier or displayTitle as key (consistent with
          // exportElementInfoWithOID)
          NSString *key = attr.identifier ?: attr.displayTitle;
          if (!key)
            continue;

          NSString *keyLower = [key lowercaseString];
          NSString *value = (NSString *)attr.value;

          if (value.length > 0) {
            // Check exact matches first
            for (NSString *targetKey in exactTextKeys) {
              if ([keyLower isEqualToString:targetKey]) {
                return value;
              }
            }
          }
        }
      }
    }
  }

  // Second pass: look for partial matches
  for (LookinAttributesGroup *group in item.attributesGroupList) {
    if (!group.attrSections)
      continue;
    for (LookinAttributesSection *section in group.attrSections) {
      if (!section.attributes)
        continue;
      for (LookinAttribute *attr in section.attributes) {
        if (attr.value && [attr.value isKindOfClass:[NSString class]]) {
          NSString *key = attr.identifier ?: attr.displayTitle;
          if (!key)
            continue;

          NSString *keyLower = [key lowercaseString];
          NSString *value = (NSString *)attr.value;

          if (value.length > 0) {
            for (NSString *targetKey in partialTextKeys) {
              if ([keyLower containsString:targetKey]) {
                return value;
              }
            }
          }
        }
      }
    }
  }
  return nil;
}

- (void)exportImageFromViewWithOID:(NSString *)oid
                        completion:(void (^)(NSString *jsonString))completion {
  if (!completion) {
    return;
  }

  LKInspectableApp *app = [LKAppsManager sharedInstance].inspectingApp;
  if (!app) {
    completion([self errorJSON:@"没有正在检查的应用"]);
    return;
  }

  NSString *finalOid = oid;
  LookinDisplayItem *item = [self findDisplayItemWithOID:oid];
  if (item && item.attributesGroupList) {
    for (LookinAttributesGroup *group in item.attributesGroupList) {
      if (!group.attrSections)
        continue;
      for (LookinAttributesSection *section in group.attrSections) {
        if (!section.attributes)
          continue;
        for (LookinAttribute *attr in section.attributes) {
          if ([attr.identifier isEqualToString:@"iv_o_o"] && attr.value) {
            finalOid = [NSString stringWithFormat:@"%@", attr.value];
            break;
          }
        }
      }
    }
  }

  unsigned long oidLong = [finalOid longLongValue];
  [[app fetchImageWithImageViewOid:oidLong]
      subscribeNext:^(id x) {
        NSImage *image = nil;
        if ([x isKindOfClass:[NSImage class]]) {
          image = (NSImage *)x;
        } else if ([x isKindOfClass:[NSData class]]) {
          image = [[NSImage alloc] initWithData:x];
        }

        if (!image) {
          completion([self errorJSON:@"无法获取图片数据"]);
          return;
        }

        // Convert to PNG data
        NSData *pngData = nil;
        // For NSImage to PNG data
        CGImageRef cgRef = [image CGImageForProposedRect:NULL
                                                 context:nil
                                                   hints:nil];
        NSBitmapImageRep *newRep =
            [[NSBitmapImageRep alloc] initWithCGImage:cgRef];
        [newRep setSize:[image size]];
        pngData = [newRep representationUsingType:NSBitmapImageFileTypePNG
                                       properties:@{}];

        if (!pngData) {
          completion([self errorJSON:@"图片格式转换失败"]);
          return;
        }

        NSString *base64 = [pngData base64EncodedStringWithOptions:0];
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        result[@"status"] = @"success";
        result[@"oid"] = oid;
        result[@"data"] = base64;

        completion([self jsonStringFromDictionary:result]);
      }
      error:^(NSError *_Nullable error) {
        completion([self
            errorJSON:[NSString stringWithFormat:@"获取图片失败: %@",
                                                 error.localizedDescription
                                                     ?: @"未知错误"]]);
      }];
}

#pragma mark - Actions

- (void)reloadViewWithCompletion:
    (void (^)(BOOL success, NSError *_Nullable error))completion {
  // 触发刷新逻辑，类似于 LKStaticWindowController 的 _handleReload 方法
  LKInspectableApp *app = [LKAppsManager sharedInstance].inspectingApp;

  if (!app) {
    NSError *error = [NSError
        errorWithDomain:@"LKMCPBridge"
                   code:-1
               userInfo:@{NSLocalizedDescriptionKey : @"没有正在检查的应用"}];
    if (completion) {
      completion(NO, error);
    }
    return;
  }

  [[app fetchHierarchyData]
      subscribeNext:^(LookinHierarchyInfo *info) {
        [[LKStaticHierarchyDataSource sharedInstance]
            reloadWithHierarchyInfo:info
                          keepState:YES];
        if (completion) {
          completion(YES, nil);
        }
      }
      error:^(NSError *_Nullable error) {
        if (completion) {
          completion(NO, error);
        }
      }];
}

#pragma mark - Helper Methods

- (LookinDisplayItem *)findDisplayItemWithOID:(NSString *)oid {
  LKStaticHierarchyDataSource *dataSource =
      [LKStaticHierarchyDataSource sharedInstance];
  LookinHierarchyInfo *hierarchyInfo = dataSource.rawHierarchyInfo;

  if (!hierarchyInfo || !hierarchyInfo.displayItems ||
      hierarchyInfo.displayItems.count == 0) {
    return nil;
  }

  for (LookinDisplayItem *item in hierarchyInfo.displayItems) {
    LookinDisplayItem *found = [self findDisplayItemWithOID:oid inItem:item];
    if (found) {
      return found;
    }
  }

  return nil;
}

- (LookinDisplayItem *)findDisplayItemWithOID:(NSString *)oid
                                       inItem:(LookinDisplayItem *)item {
  if (!item) {
    return nil;
  }

  // 检查当前 item 的 oid
  NSNumber *itemOid = nil;
  if (item.layerObject) {
    itemOid = @(item.layerObject.oid);
  } else if (item.viewObject) {
    itemOid = @(item.viewObject.oid);
  }

  if (itemOid &&
      [[NSString stringWithFormat:@"%@", itemOid] isEqualToString:oid]) {
    return item;
  }

  for (LookinDisplayItem *subitem in item.subitems) {
    LookinDisplayItem *found = [self findDisplayItemWithOID:oid inItem:subitem];
    if (found) {
      return found;
    }
  }

  return nil;
}

- (NSString *)jsonStringFromDictionary:(NSDictionary *)dictionary {
  NSError *error;
  NSData *jsonData =
      [NSJSONSerialization dataWithJSONObject:dictionary
                                      options:NSJSONWritingPrettyPrinted
                                        error:&error];
  if (error) {
    return
        [self errorJSON:[NSString stringWithFormat:@"JSON 序列化失败: %@",
                                                   error.localizedDescription]];
  }

  return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (NSString *)errorJSON:(NSString *)message {
  NSDictionary *error = @{@"status" : @"error", @"message" : message};
  return [self jsonStringFromDictionary:error];
}

- (NSDictionary *)serializeColor:(LookinColor *)color {
  if (!color) {
    return nil;
  }

#if TARGET_OS_IPHONE
  CGFloat r, g, b, a;
  if ([color getRed:&r green:&g blue:&b alpha:&a]) {
    return @{
      @"red" : @(r * 255),
      @"green" : @(g * 255),
      @"blue" : @(b * 255),
      @"alpha" : @(a),
      @"hex" : [NSString stringWithFormat:@"#%02X%02X%02X", (int)(r * 255),
                                          (int)(g * 255), (int)(b * 255)]
    };
  }
#elif TARGET_OS_MAC
  NSColor *rgbColor =
      [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
  if (rgbColor) {
    return @{
      @"red" : @(rgbColor.redComponent * 255),
      @"green" : @(rgbColor.greenComponent * 255),
      @"blue" : @(rgbColor.blueComponent * 255),
      @"alpha" : @(rgbColor.alphaComponent),
      @"hex" : [NSString stringWithFormat:@"#%02X%02X%02X",
                                          (int)(rgbColor.redComponent * 255),
                                          (int)(rgbColor.greenComponent * 255),
                                          (int)(rgbColor.blueComponent * 255)]
    };
  }
#endif

  return nil;
}

- (id)serializeAttributeValue:(LookinAttribute *)attr {
  if (!attr.value) {
    return nil;
  }

  // 根据 attrType 序列化不同类型的值
  // 注意: LookinAttrType 的具体值需要查看定义，这里使用常见的类型

  // 字符串类型
  if ([attr.value isKindOfClass:[NSString class]]) {
    return attr.value;
  }

  // 数字类型
  if ([attr.value isKindOfClass:[NSNumber class]]) {
    return attr.value;
  }

  // 颜色类型
  if ([attr.value isKindOfClass:[LookinColor class]]) {
    return [self serializeColor:(LookinColor *)attr.value];
  }

  // CGRect / NSRect
  if ([attr.value isKindOfClass:[NSValue class]]) {
    NSValue *value = (NSValue *)attr.value;
#if TARGET_OS_IPHONE
    if (strcmp(value.objCType, @encode(CGRect)) == 0) {
      CGRect rect = [value CGRectValue];
      return @{
        @"x" : @(rect.origin.x),
        @"y" : @(rect.origin.y),
        @"width" : @(rect.size.width),
        @"height" : @(rect.size.height)
      };
    }
    if (strcmp(value.objCType, @encode(CGSize)) == 0) {
      CGSize size = [value CGSizeValue];
      return @{@"width" : @(size.width), @"height" : @(size.height)};
    }
    if (strcmp(value.objCType, @encode(CGPoint)) == 0) {
      CGPoint point = [value CGPointValue];
      return @{@"x" : @(point.x), @"y" : @(point.y)};
    }
#elif TARGET_OS_MAC
    if (strcmp(value.objCType, @encode(NSRect)) == 0) {
      NSRect rect = [value rectValue];
      return @{
        @"x" : @(rect.origin.x),
        @"y" : @(rect.origin.y),
        @"width" : @(rect.size.width),
        @"height" : @(rect.size.height)
      };
    }
    if (strcmp(value.objCType, @encode(NSSize)) == 0) {
      NSSize size = [value sizeValue];
      return @{@"width" : @(size.width), @"height" : @(size.height)};
    }
    if (strcmp(value.objCType, @encode(NSPoint)) == 0) {
      NSPoint point = [value pointValue];
      return @{@"x" : @(point.x), @"y" : @(point.y)};
    }
#endif
  }

  // 字体类型
#if TARGET_OS_IPHONE
  if ([attr.value isKindOfClass:[UIFont class]]) {
    UIFont *font = (UIFont *)attr.value;
    return @{
      @"fontName" : font.fontName ?: @"",
      @"familyName" : font.familyName ?: @"",
      @"pointSize" : @(font.pointSize)
    };
  }
#elif TARGET_OS_MAC
  if ([attr.value isKindOfClass:[NSFont class]]) {
    NSFont *font = (NSFont *)attr.value;
    return @{
      @"fontName" : font.fontName ?: @"",
      @"familyName" : font.familyName ?: @"",
      @"pointSize" : @(font.pointSize)
    };
  }
#endif

  // 默认: 尝试转换为字符串
  return [attr.value description];
}

@end
