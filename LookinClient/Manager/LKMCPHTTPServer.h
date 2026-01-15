//
//  LKMCPHTTPServer.h
//  Lookin
//
//  Created for MCP Integration - HTTP Server
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * MCP HTTP 服务器，用于暴露 LKMCPBridge 的功能通过 HTTP 接口
 * 默认监听 http://localhost:10086
 */
@interface LKMCPHTTPServer : NSObject

+ (instancetype)sharedInstance;

/**
 * 启动 HTTP 服务器
 * @param port 监听端口，默认 10086
 */
- (void)startServerOnPort:(NSUInteger)port;

/**
 * 停止 HTTP 服务器
 */
- (void)stopServer;

/**
 * 服务器是否正在运行
 */
@property(nonatomic, assign, readonly) BOOL isRunning;

/**
 * 当前监听的端口
 */
@property(nonatomic, assign, readonly) NSUInteger port;

@end

NS_ASSUME_NONNULL_END
