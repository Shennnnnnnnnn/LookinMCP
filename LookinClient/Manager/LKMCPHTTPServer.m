//
//  LKMCPHTTPServer.m
//  Lookin
//
//  Created for MCP Integration - HTTP Server
//

#import "LKMCPHTTPServer.h"
#import "LKMCPBridge.h"
#import <GCDWebServer/GCDWebServer.h>
#import <GCDWebServer/GCDWebServerDataResponse.h>

@interface LKMCPHTTPServer ()

@property(nonatomic, strong) GCDWebServer *webServer;
@property(nonatomic, assign) BOOL isRunning;
@property(nonatomic, assign) NSUInteger port;

@end

@implementation LKMCPHTTPServer

+ (instancetype)sharedInstance {
  static LKMCPHTTPServer *instance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[LKMCPHTTPServer alloc] init];
  });
  return instance;
}

- (instancetype)init {
  if (self = [super init]) {
    _webServer = [[GCDWebServer alloc] init];
    _isRunning = NO;
    _port = 0;
    [self setupRoutes];
  }
  return self;
}

- (void)setupRoutes {
  LKMCPBridge *bridge = [LKMCPBridge sharedInstance];

  // GET /api/hierarchy
  [self.webServer
      addHandlerForMethod:@"GET"
                     path:@"/api/hierarchy"
             requestClass:[GCDWebServerRequest class]
             processBlock:^GCDWebServerResponse *(
                 GCDWebServerRequest *request) {
               NSInteger maxDepth =
                   [request.query[@"max_depth"] integerValue] ?: -1;
               NSString *filterClass = request.query[@"filter_class"];
               NSString *elementID = request.query[@"element_id"];

               NSString *jsonString =
                   [bridge exportHierarchyWithMaxDepth:maxDepth
                                           filterClass:filterClass
                                             elementID:elementID];

               return [GCDWebServerDataResponse
                   responseWithJSONObject:[self parseJSON:jsonString]];
             }];

  // GET /api/element/:oid/image
  [self.webServer
      addHandlerForMethod:@"GET"
                pathRegex:@"^/api/element/(.+)/image$"
             requestClass:[GCDWebServerRequest class]
             processBlock:^GCDWebServerResponse *(
                 __kindof GCDWebServerRequest *request) {
               NSString *path = request.path;
               // Extract OID: /api/element/123/image -> 123
               // Using regex grouping would be better but pathRegex handler
               // doesn't pass groups easily in this block signature typically
               // without custom request class or parsing path again. Path
               // format: /api/element/{oid}/image

               NSArray *components = [path componentsSeparatedByString:@"/"];
               // components: ["", "api", "element", "{oid}", "image"]
               if (components.count < 4) {
                 return [self errorResponse:@"Invalid path"];
               }
               NSString *oid = components[3];

               if (!oid || oid.length == 0) {
                 return [self errorResponse:@"Missing element OID"];
               }

               __block GCDWebServerResponse *response = nil;
               dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

               [bridge exportImageFromViewWithOID:oid
                                       completion:^(NSString *jsonString) {
                                         response = [GCDWebServerDataResponse
                                             responseWithJSONObject:
                                                 [self parseJSON:jsonString]];
                                         dispatch_semaphore_signal(semaphore);
                                       }];

               dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
               return response;
             }];

  // GET /api/element/:oid/screenshot
  [self.webServer
      addHandlerForMethod:@"GET"
                pathRegex:@"^/api/element/(.+)/screenshot$"
             requestClass:[GCDWebServerRequest class]
             processBlock:^GCDWebServerResponse *(
                 __kindof GCDWebServerRequest *request) {
               NSString *path = request.path;
               NSArray *components = [path componentsSeparatedByString:@"/"];
               // components: ["", "api", "element", "{oid}", "screenshot"]
               if (components.count < 4) {
                 return [self errorResponse:@"Invalid path"];
               }
               NSString *oid = components[3];

               if (!oid || oid.length == 0) {
                 return [self errorResponse:@"Missing element OID"];
               }

               NSString *jsonString = [bridge exportScreenshotWithOID:oid];
               return [GCDWebServerDataResponse
                   responseWithJSONObject:[self parseJSON:jsonString]];
             }];

  // GET /api/element/:oid
  [self.webServer
      addHandlerForMethod:@"GET"
                pathRegex:@"^/api/element/([^/]+)$"
             requestClass:[GCDWebServerRequest class]
             processBlock:^GCDWebServerResponse *(
                 __kindof GCDWebServerRequest *request) {
               // 从路径中提取 OID
               NSString *path = request.path;
               NSString *oid =
                   [path stringByReplacingOccurrencesOfString:@"/api/element/"
                                                   withString:@""];

               if (!oid || oid.length == 0) {
                 return [self errorResponse:@"Missing element OID"];
               }

               NSString *jsonString = [bridge exportElementInfoWithOID:oid];
               return [GCDWebServerDataResponse
                   responseWithJSONObject:[self parseJSON:jsonString]];
             }];

  // GET /api/relative_position
  [self.webServer
      addHandlerForMethod:@"GET"
                     path:@"/api/relative_position"
             requestClass:[GCDWebServerRequest class]
             processBlock:^GCDWebServerResponse *(
                 GCDWebServerRequest *request) {
               NSString *oid1 = request.query[@"element_id_1"];
               NSString *oid2 = request.query[@"element_id_2"];

               if (!oid1 || !oid2) {
                 return [self
                     errorResponse:@"Missing element_id_1 or element_id_2"];
               }

               NSString *jsonString =
                   [bridge calculateRelativePositionBetween:oid1 and:oid2];

               return [GCDWebServerDataResponse
                   responseWithJSONObject:[self parseJSON:jsonString]];
             }];

  // POST /api/reload
  [self.webServer
      addHandlerForMethod:@"POST"
                     path:@"/api/reload"
             requestClass:[GCDWebServerRequest class]
             processBlock:^GCDWebServerResponse *(
                 GCDWebServerRequest *request) {
               __block GCDWebServerResponse *response = nil;
               dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

               [bridge
                   reloadViewWithCompletion:^(BOOL success, NSError *error) {
                     if (success) {
                       response =
                           [GCDWebServerDataResponse responseWithJSONObject:@{
                             @"status" : @"success",
                             @"message" : @"视图刷新成功"
                           }];
                     } else {
                       response = [self errorResponse:error.localizedDescription
                                                          ?: @"刷新失败"];
                     }
                     dispatch_semaphore_signal(semaphore);
                   }];

               dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
               return response;
             }];

  // GET /api/search
  [self.webServer
      addHandlerForMethod:@"GET"
                     path:@"/api/search"
             requestClass:[GCDWebServerRequest class]
             processBlock:^GCDWebServerResponse *(
                 GCDWebServerRequest *request) {
               NSString *query = request.query[@"query"];
               NSString *searchType = request.query[@"search_type"] ?: @"all";

               if (!query) {
                 return [self errorResponse:@"Missing query parameter"];
               }

               NSString *jsonString =
                   [bridge searchElementsWithQuery:query type:searchType];

               return [GCDWebServerDataResponse
                   responseWithJSONObject:[self parseJSON:jsonString]];
             }];

  // Health check
  [self.webServer
      addHandlerForMethod:@"GET"
                     path:@"/health"
             requestClass:[GCDWebServerRequest class]
             processBlock:^GCDWebServerResponse *(
                 GCDWebServerRequest *request) {
               return [GCDWebServerDataResponse responseWithJSONObject:@{
                 @"status" : @"ok",
                 @"service" : @"Lookin MCP Server"
               }];
             }];
}

- (void)startServerOnPort:(NSUInteger)port {
  if (self.isRunning) {
    NSLog(@"MCP HTTP Server 已经在运行中，端口: %lu", (unsigned long)self.port);
    return;
  }

  NSError *error = nil;
  BOOL success = [self.webServer startWithPort:port bonjourName:nil];

  if (success) {
    self.isRunning = YES;
    self.port = port;
    NSLog(@"✅ MCP HTTP Server 启动成功，监听: http://localhost:%lu",
          (unsigned long)port);
    NSLog(@"   - Health Check: http://localhost:%lu/health",
          (unsigned long)port);
    NSLog(@"   - API Endpoint: http://localhost:%lu/api/*",
          (unsigned long)port);
  } else {
    NSLog(@"❌ MCP HTTP Server 启动失败: %@", error);
  }
}

- (void)stopServer {
  if (!self.isRunning) {
    return;
  }

  [self.webServer stop];
  self.isRunning = NO;
  self.port = 0;
  NSLog(@"MCP HTTP Server 已停止");
}

#pragma mark - Helper Methods

- (NSDictionary *)parseJSON:(NSString *)jsonString {
  if (!jsonString) {
    return @{@"error" : @"Empty response"};
  }

  NSData *data = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
  NSError *error = nil;
  id json = [NSJSONSerialization JSONObjectWithData:data
                                            options:0
                                              error:&error];

  if (error || ![json isKindOfClass:[NSDictionary class]]) {
    return @{@"error" : @"Invalid JSON", @"raw" : jsonString};
  }

  return json;
}

- (GCDWebServerDataResponse *)errorResponse:(NSString *)message {
  return [GCDWebServerDataResponse
      responseWithJSONObject:@{@"status" : @"error", @"message" : message}];
}

- (void)dealloc {
  [self stopServer];
}

@end
