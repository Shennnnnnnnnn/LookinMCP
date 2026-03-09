import Foundation
import MCP
import GCDWebServer

@objc
public class LKMCPManager: NSObject {
    @objc public static let sharedManager = LKMCPManager()
    
    // Reference to the server process
    private var task: Task<Void, Error>?
    private var server: Server?
    private var webServer: GCDWebServer?
    private var mcpTransport: StatelessHTTPServerTransport?
    private var isRunning = false
    
    @objc public var mcpServerEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "mcpServerEnabled")
        }
    }
    
    @objc public var mcpServerPort: Int {
        get {
            let port = UserDefaults.standard.integer(forKey: "mcpServerPort")
            return port > 0 ? port : 47199
        }
    }
    
    private override init() {
        super.init()
    }
    
    @objc public func startServerIfNeeded() {
        guard mcpServerEnabled else { return }
        guard !isRunning else { return }
        
        startServer()
    }
    
    @objc public func stopServer() {
        task?.cancel()
        task = nil
        server = nil
        webServer?.stop()
        webServer = nil
        mcpTransport = nil
        isRunning = false
    }
    
    @objc public func toggleServerIfNeeded() {
        if mcpServerEnabled {
            if !isRunning {
                startServer()
            }
        } else {
            if isRunning {
                stopServer()
            }
        }
    }
    
    private func startServer() {
        self.isRunning = true
        
        // Start GCDWebServer
        let web = GCDWebServer()
        self.webServer = web
        
        web.addHandler(forMethod: "POST", path: "/mcp", request: GCDWebServerDataRequest.self, asyncProcessBlock: { [weak self] (req, completionBlock) in
            guard let self = self, let dataReq = req as? GCDWebServerDataRequest else {
                completionBlock(GCDWebServerDataResponse(jsonObject: ["error": "Invalid request"])!)
                return
            }
            
            Task {
                // Check if this is an "initialize" request
                var isInitialize = false
                if let jsonObject = try? JSONSerialization.jsonObject(with: dataReq.data, options: []) {
                    if let dict = jsonObject as? [String: Any], let method = dict["method"] as? String, method == "initialize" {
                        isInitialize = true
                    } else if let array = jsonObject as? [[String: Any]] {
                        for item in array {
                            if let method = item["method"] as? String, method == "initialize" {
                                isInitialize = true
                                break
                            }
                        }
                    }
                }
                
                // If it's an initialize request, we must reset the Server instance so it doesn't complain
                if isInitialize {
                    await self.restartMCPServerTask()
                }
                
                guard let transport = self.mcpTransport else {
                    completionBlock(GCDWebServerDataResponse(jsonObject: ["error": "Server not ready"])!)
                    return
                }
                
                var mcpHeaders: [String: String] = [:]
                if let reqHeaders = dataReq.headers as? [String: String] {
                    for (k, v) in reqHeaders {
                        mcpHeaders[k.lowercased()] = v
                    }
                }
                if mcpHeaders["content-type"] == nil {
                    mcpHeaders["content-type"] = dataReq.contentType ?? "application/json"
                }
                
                // Create MCP HTTPRequest
                let mcpReq = HTTPRequest(
                    method: "POST",
                    headers: mcpHeaders,
                    body: dataReq.data
                )
                
                let mcpRes = await transport.handleRequest(mcpReq)
                
                let statusCode = mcpRes.statusCode
                var resHeaders: [String: String] = [:]
                for header in mcpRes.headers {
                    resHeaders[header.key.lowercased()] = header.value
                }
                
                if let body = mcpRes.bodyData {
                    let response = GCDWebServerDataResponse(data: body, contentType: resHeaders["content-type"] ?? "application/json")
                    response.statusCode = statusCode
                    for (k, v) in resHeaders {
                        response.setValue(v, forAdditionalHeader: k)
                    }
                    completionBlock(response)
                } else {
                    let response = GCDWebServerResponse(statusCode: statusCode)
                    for (k, v) in resHeaders {
                        response.setValue(v, forAdditionalHeader: k)
                    }
                    completionBlock(response)
                }
            }
        })
        
        let portToUse = UInt(self.mcpServerPort)
        web.start(withPort: portToUse, bonjourName: nil)
        
        Task {
            await self.restartMCPServerTask()
        }
    }
    
    private func restartMCPServerTask() async {
        task?.cancel()
        
        let newServer = Server(
            name: "lookin-mcp-server",
            version: "1.0.0",
            capabilities: .init(
                tools: .init(listChanged: true)
            )
        )
        self.server = newServer
        
        await setupTools(server: newServer)
        
        let transport = StatelessHTTPServerTransport()
        self.mcpTransport = transport
        
        task = Task {
            try? await newServer.start(transport: transport)
        }
    }
    
    private func setupTools(server: Server) async {
        await server.withMethodHandler(ListTools.self) { _ in
            let tools = [
                Tool(
                    name: "get_hierarchy",
                    description: "获取当前页面的视图层级结构，包含所有元素的基本信息（类名、frame、是否可见等）",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "max_depth": .object([
                                "type": .string("integer"),
                                "description": .string("最大层级深度，默认为 -1（无限制）")
                            ]),
                            "filter_class": .object([
                                "type": .string("string"),
                                "description": .string("可选：按类名过滤视图，例如 'UILabel' 或 'UIButton'")
                            ])
                        ])
                    ])
                ),
                Tool(
                    name: "get_element_info",
                    description: "获取指定元素的详细信息，包括所有属性、约束、子视图等",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "element_id": .object([
                                "type": .string("string"),
                                "description": .string("元素的唯一标识符（oid）")
                            ])
                        ]),
                        "required": .array([.string("element_id")])
                    ])
                ),
                Tool(
                    name: "get_relative_position",
                    description: "获取两个元素之间的相对位置关系",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "element_id_1": .object([
                                "type": .string("string"),
                                "description": .string("第一个元素的唯一标识符")
                            ]),
                            "element_id_2": .object([
                                "type": .string("string"),
                                "description": .string("第二个元素的唯一标识符")
                            ])
                        ]),
                        "required": .array([.string("element_id_1"), .string("element_id_2")])
                    ])
                ),
                Tool(
                    name: "reload_view",
                    description: "刷新视图层级，重新获取最新的界面状态",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([:])
                    ])
                ),
                Tool(
                    name: "search_elements",
                    description: "搜索包含指定文本或类名的元素",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "query": .object([
                                "type": .string("string"),
                                "description": .string("搜索关键词，可以是类名、文本内容或标识符")
                            ]),
                            "search_type": .object([
                                "type": .string("string"),
                                "description": .string("搜索类型：all（全部）、class（类名）、text（文本）、identifier（标识符）、size（尺寸，格式如 100x200）")
                            ])
                        ]),
                        "required": .array([.string("query")])
                    ])
                ),
                Tool(
                    name: "modify_element_attribute",
                    description: "修改元素的属性值（例如 frame、backgroundColor、alpha 等）",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "element_id": .object([
                                "type": .string("string"),
                                "description": .string("元素的唯一标识符")
                            ]),
                            "attribute": .object([
                                "type": .string("string"),
                                "description": .string("要修改的属性名称")
                            ]),
                            "value": .object([
                                "type": .string("string"),
                                "description": .string("新的属性值")
                            ])
                        ]),
                        "required": .array([.string("element_id"), .string("attribute"), .string("value")])
                    ])
                ),
                Tool(
                    name: "save_image",
                    description: "将指定元素的图片将会保存到本地目录（默认为当前目录）",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "element_id": .object([
                                "type": .string("string"),
                                "description": .string("元素的唯一标识符")
                            ]),
                            "directory": .object([
                                "type": .string("string"),
                                "description": .string("保存图片的目录路径，默认为当前工作目录")
                            ]),
                            "filename": .object([
                                "type": .string("string"),
                                "description": .string("保存的文件名，默认为 element_{oid}.png")
                            ])
                        ]),
                        "required": .array([.string("element_id")])
                    ])
                ),
                Tool(
                    name: "export_screenshot",
                    description: "将指定元素及其所有子元素的层级渲染截图导出为 PNG 图片并保存到本地目录。与 save_image 不同，此功能不仅限于 UIImageView，可对任何类型的视图进行截图导出。如果未配置路径，将默认保存在当前目录下。",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "element_id": .object([
                                "type": .string("string"),
                                "description": .string("元素的唯一标识符（oid）")
                            ]),
                            "directory": .object([
                                "type": .string("string"),
                                "description": .string("保存图片的目录路径，默认为当前工作目录下的 screenshots 文件夹")
                            ]),
                            "filename": .object([
                                "type": .string("string"),
                                "description": .string("保存的文件名（包含 .png），默认为 screenshot_{oid}.png")
                            ])
                        ]),
                        "required": .array([.string("element_id")])
                    ])
                )
            ]
            return .init(tools: tools)
        }
        
        await server.withMethodHandler(CallTool.self) { params in
            switch params.name {
            case "get_hierarchy":
                let maxDepth = params.arguments?["max_depth"]?.intValue ?? -1
                let filterClass = params.arguments?["filter_class"]?.stringValue
                return await self.performLocalHTTPRequest(path: "/api/hierarchy", queryItems: [
                    URLQueryItem(name: "max_depth", value: "\(maxDepth)"),
                    URLQueryItem(name: "filter_class", value: filterClass)
                ])
                
            case "get_element_info":
                guard let elementId = params.arguments?["element_id"]?.stringValue else {
                    return .init(content: [.text("Missing element_id")], isError: true)
                }
                return await self.performLocalHTTPRequest(path: "/api/element/\(elementId)", queryItems: [])
                
            case "get_relative_position":
                guard let el1 = params.arguments?["element_id_1"]?.stringValue,
                      let el2 = params.arguments?["element_id_2"]?.stringValue else {
                    return .init(content: [.text("Missing element ids")], isError: true)
                }
                return await self.performLocalHTTPRequest(path: "/api/relative_position", queryItems: [
                    URLQueryItem(name: "element_id_1", value: el1),
                    URLQueryItem(name: "element_id_2", value: el2)
                ])
                
            case "reload_view":
                // Original script was using POST /api/reload
                return await self.performLocalHTTPRequest(path: "/api/reload", queryItems: [], method: "POST")
                
            case "search_elements":
                guard let query = params.arguments?["query"]?.stringValue else {
                    return .init(content: [.text("Missing query")], isError: true)
                }
                let searchType = params.arguments?["search_type"]?.stringValue ?? "all"
                return await self.performLocalHTTPRequest(path: "/api/search", queryItems: [
                    URLQueryItem(name: "query", value: query),
                    URLQueryItem(name: "search_type", value: searchType)
                ])
                
            case "modify_element_attribute":
                return .init(content: [.text("修改元素属性功能暂未实现")], isError: true)
                
            case "save_image":
                guard let elementId = params.arguments?["element_id"]?.stringValue else {
                    return .init(content: [.text("Missing element_id")], isError: true)
                }
                let directory = params.arguments?["directory"]?.stringValue ?? "."
                let filename = params.arguments?["filename"]?.stringValue ?? "element_\(elementId).png"
                
                // Fetch image base64
                let result = await self.fetchLocalHTTP(path: "/api/element/\(elementId)/image", queryItems: [])
                
                switch result {
                case .success(let data):
                    do {
                        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                        if let status = json?["status"] as? String, status == "success",
                           let base64Data = json?["data"] as? String,
                           let imageData = Data(base64Encoded: base64Data) {
                            
                            let dirURL = URL(fileURLWithPath: directory)
                            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)
                            let fileURL = dirURL.appendingPathComponent(filename)
                            try imageData.write(to: fileURL)
                            
                            let responseObj = [
                                "status": "success",
                                "message": "Image saved to \(fileURL.path)",
                                "path": fileURL.path
                            ]
                            let responseData = try JSONSerialization.data(withJSONObject: responseObj, options: .prettyPrinted)
                            let text = String(data: responseData, encoding: .utf8) ?? ""
                            return .init(content: [.text(text)], isError: false)
                        } else {
                            let msg = (json?["message"] as? String) ?? "Unknown error"
                            return .init(content: [.text(msg)], isError: true)
                        }
                    } catch {
                        return .init(content: [.text("Parse error: \(error)")], isError: true)
                    }
                case .failure(let error):
                    return .init(content: [.text("Fetch error: \(error)")], isError: true)
                }
                
            case "export_screenshot":
                guard let elementId = params.arguments?["element_id"]?.stringValue else {
                    return .init(content: [.text("Missing element_id")], isError: true)
                }
                let directory = params.arguments?["directory"]?.stringValue ?? "screenshots"
                let filename = params.arguments?["filename"]?.stringValue ?? "screenshot_\(elementId).png"
                
                // Fetch screenshot base64
                let result = await self.fetchLocalHTTP(path: "/api/element/\(elementId)/screenshot", queryItems: [])
                
                switch result {
                case .success(let data):
                    do {
                        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                        if let status = json?["status"] as? String, status == "success",
                           let base64Data = json?["data"] as? String,
                           let imageData = Data(base64Encoded: base64Data) {
                            
                            let dirURL = URL(fileURLWithPath: directory)
                            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)
                            let fileURL = dirURL.appendingPathComponent(filename)
                            try imageData.write(to: fileURL)
                            
                            let responseObj = [
                                "status": "success",
                                "message": "Screenshot saved to \(fileURL.path)",
                                "path": fileURL.path
                            ]
                            let responseData = try JSONSerialization.data(withJSONObject: responseObj, options: .prettyPrinted)
                            let text = String(data: responseData, encoding: .utf8) ?? ""
                            return .init(content: [.text(text)], isError: false)
                        } else {
                            let msg = (json?["message"] as? String) ?? "Unknown error"
                            return .init(content: [.text(msg)], isError: true)
                        }
                    } catch {
                        return .init(content: [.text("Parse error: \(error)")], isError: true)
                    }
                case .failure(let error):
                    return .init(content: [.text("Fetch error: \(error)")], isError: true)
                }
                
            default:
                return .init(content: [.text("Unknown tool: \(params.name)")], isError: true)
            }
        }
    }
    
    private func fetchLocalHTTP(path: String, queryItems: [URLQueryItem], method: String = "GET") async -> Result<Data, Error> {
        var components = URLComponents(string: "http://localhost:10086\(path)")!
        if !queryItems.isEmpty {
            let filteredItems = queryItems.filter { $0.value != nil }
            if !filteredItems.isEmpty {
                components.queryItems = filteredItems
            }
        }
        
        guard let url = components.url else {
            return .failure(NSError(domain: "MCP", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                return .success(data)
            } else {
                let text = String(data: data, encoding: .utf8) ?? "Unknown HTTP ERROR"
                return .failure(NSError(domain: "MCP", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: text]))
            }
        } catch {
            return .failure(error)
        }
    }
    
    private func performLocalHTTPRequest(path: String, queryItems: [URLQueryItem], method: String = "GET") async -> CallTool.Result {
        let result = await fetchLocalHTTP(path: path, queryItems: queryItems, method: method)
        switch result {
        case .success(let data):
            if let text = String(data: data, encoding: .utf8) {
                return .init(content: [.text(text)], isError: false)
            } else {
                return .init(content: [.text("Failed to decode response")], isError: true)
            }
        case .failure(let error):
            return .init(content: [.text("Request failed: \(error.localizedDescription)")], isError: true)
        }
    }
}
