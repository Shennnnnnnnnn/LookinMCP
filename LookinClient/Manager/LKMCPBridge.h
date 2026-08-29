//
//  LKMCPBridge.h
//  Lookin
//
//  Created for MCP Integration
//

#import <Foundation/Foundation.h>

@class LookinHierarchyInfo, LookinDisplayItem, LookinDisplayItemDetail;

NS_ASSUME_NONNULL_BEGIN

/**
 * MCP 桥接类，用于将 Lookin 的数据暴露给 MCP 服务器
 */
@interface LKMCPBridge : NSObject

+ (instancetype)sharedInstance;

#pragma mark - Data Export

/**
 * 导出当前的视图层级结构为 JSON
 * @param maxDepth 最大深度，-1 表示无限制
 * @param filterClass 可选的类名过滤器
 * @param elementID 目标元素的 OID（可选，如果提供则只导出该节点及其子节点）
 * @return JSON 字符串
 */
- (NSString *)exportHierarchyWithMaxDepth:(NSInteger)maxDepth
                              filterClass:(nullable NSString *)filterClass
                                elementID:(nullable NSString *)elementID;

/**
 * 导出指定元素的详细信息
 * @param oid 元素的唯一标识符
 * @return JSON 字符串
 */
- (NSString *)exportElementInfoWithOID:(NSString *)oid;

/**
 * 计算两个元素的相对位置
 * @param oid1 第一个元素的 OID
 * @param oid2 第二个元素的 OID
 * @return JSON 字符串，包含相对位置信息
 */
- (NSString *)calculateRelativePositionBetween:(NSString *)oid1
                                           and:(NSString *)oid2;

/**
 * 搜索元素
 * @param query 搜索关键词
 * @param searchType 搜索类型：all, class, text, identifier
 * @return JSON 字符串，包含搜索结果
 */
- (NSString *)searchElementsWithQuery:(NSString *)query
                                 type:(NSString *)searchType;

/**
 * 导出指定 ImageView 的图片
 * @param oid 元素的 OID
 * @param completion 回调，返回 JSON 字符串
 */
- (void)exportImageFromViewWithOID:(NSString *)oid
                        completion:(void (^)(NSString *jsonString))completion;

/**
 * 尝试将当前层级中所有 UIImageView/子类的 image 导出为 PNG；nil/失败项进入错误清单。
 * @param directory 目标文件夹
 * @param completion 回调，返回导出清单 JSON
 */
- (void)exportAllImagesToDirectory:(NSString *)directory
                        completion:(void (^)(NSString *jsonString))completion;

/// 导出指定 OID 视图及其子视图的截图 (PNG 格式的 Base64 编码)
- (NSString *)exportScreenshotWithOID:(NSString *)oid;

#pragma mark - Actions

/**
 * 触发视图刷新（相当于点击 Reload 按钮）
 * @param completion 完成回调
 */
- (void)reloadViewWithCompletion:(void (^)(BOOL success,
                                           NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
