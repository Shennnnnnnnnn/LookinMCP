import Foundation
import MCP
import GCDWebServer

@objc
public class LKMCPManager: NSObject {
    @objc public static let sharedManager = LKMCPManager()
    private static let apiServerPort: UInt = 10086
    
    // Reference to the server process
    private var task: Task<Void, Error>?
    private var server: Server?
    private var webServer: GCDWebServer?
    private var mcpTransport: StatelessHTTPServerTransport?
    @objc public private(set) var isRunning = false

    @objc public var apiServerURL: String {
        return "http://127.0.0.1:\(Self.apiServerPort)"
    }

    @objc public var mcpServerURL: String {
        return "http://127.0.0.1:\(mcpServerPort)/mcp"
    }
    
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
        LKMCPHTTPServer.sharedInstance().stop()
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

    @objc public func restartServerIfNeeded() {
        stopServer()
        startServerIfNeeded()
    }
    
    private func startServer() {
        let apiServer = LKMCPHTTPServer.sharedInstance()
        apiServer.start(onPort: Self.apiServerPort)
        guard apiServer.isRunning else { return }
        
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
                for (key, value) in dataReq.headers {
                    mcpHeaders[key.lowercased()] = value
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
        
        do {
            try web.start(options: [
                GCDWebServerOption_Port: UInt(self.mcpServerPort),
                GCDWebServerOption_BindToLocalhost: true
            ])
        } catch {
            apiServer.stop()
            self.webServer = nil
            NSLog("Lookin MCP server failed to start: %@", error.localizedDescription)
            return
        }

        self.isRunning = true
        
        Task {
            await self.restartMCPServerTask()
        }
    }
    
    private func restartMCPServerTask() async {
        task?.cancel()
        
        let newServer = Server(
            name: "lookin-mcp-server",
            version: "1.0.0",
            instructions: "Use get_status when Lookin readiness is uncertain. For UI reproduction, prefer one capture_ui_context call so screenshot and hierarchy describe the same UI state. Use export_all_images when original UIImageView assets are needed. Keep hierarchy queries bounded by element_id or max_depth. Reload only before final validation or capture. File-producing tools write only to the directory supplied by the user.",
            capabilities: .init(
                tools: .init(listChanged: false)
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
                    name: "get_status",
                    description: "Preflight Lookin and report whether an inspected UI hierarchy is ready.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([:])
                    ])
                ),
                Tool(
                    name: "get_ui_context",
                    description: "Get a bounded, AI-oriented snapshot with hierarchy, root IDs, element counts, and focused details. Prefer this for UI reproduction.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "max_depth": .object([
                                "type": .string("integer"),
                                "description": .string("Maximum depth, default 8. Use -1 only when necessary.")
                            ]),
                            "element_id": .object([
                                "type": .string("string"),
                                "description": .string("Optional component root OID.")
                            ])
                        ])
                    ])
                ),
                Tool(
                    name: "get_hierarchy",
                    description: "Get class, text, frame, visibility, and child relationships. Scope the response by depth or element ID.",
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
                            ]),
                            "element_id": .object([
                                "type": .string("string"),
                                "description": .string("Optional subtree root OID.")
                            ])
                        ])
                    ])
                ),
                Tool(
                    name: "get_element_info",
                    description: "Inspect one element's exact frame, text, colors, typography, border, corner radius, hierarchy links, and effective constraints.",
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
                    description: "Compare two root-coordinate axis-aligned frames. Returns stable horizontal, vertical, containment, touching, minimum-distance, overlap-area, and coverage fields.",
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
                    description: "Refresh the hierarchy from the inspected app. Call once before final validation or capture.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([:])
                    ])
                ),
                Tool(
                    name: "search_elements",
                    description: "Find element OIDs by text, class, identifier, or size before focused inspection.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "query": .object([
                                "type": .string("string"),
                                "description": .string("搜索关键词，可以是类名、文本内容或标识符")
                            ]),
                            "search_type": .object([
                                "type": .string("string"),
                                "enum": .array([
                                    .string("all"), .string("class"), .string("text"),
                                    .string("identifier"), .string("size")
                                ]),
                                "description": .string("Search field, default all.")
                            ])
                        ]),
                        "required": .array([.string("query")])
                    ])
                ),
                Tool(
                    name: "save_image",
                    description: "Save the image content owned by an image element to a local file.",
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
                    name: "export_all_images",
                    description: "Export image values from every UIImageView or subclass in the current hierarchy as PNG files; nil and failed items are returned in the error list.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "directory": .object([
                                "type": .string("string"),
                                "description": .string("Directory for exported PNG files.")
                            ])
                        ]),
                        "required": .array([.string("directory")])
                    ])
                ),
                Tool(
                    name: "export_screenshot",
                    description: "Save the rendered screenshot for an element and its descendants. Use the returned absolute path as visual evidence.",
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
                        "required": .array([.string("element_id"), .string("directory")])
                    ])
                ),
                Tool(
                    name: "capture_ui_context",
                    description: "Create a synchronized UI reproduction bundle containing screenshot.png, context.json, element.json, and manifest.json.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "directory": .object([
                                "type": .string("string"),
                                "description": .string("Directory for capture artifacts.")
                            ]),
                            "element_id": .object([
                                "type": .string("string"),
                                "description": .string("Optional component root OID.")
                            ]),
                            "max_depth": .object([
                                "type": .string("integer"),
                                "description": .string("Maximum hierarchy depth, default 8.")
                            ]),
                            "refresh": .object([
                                "type": .string("boolean"),
                                "description": .string("Refresh once before capture, default true.")
                            ])
                        ]),
                        "required": .array([.string("directory")])
                    ])
                )
            ]
            return .init(tools: tools)
        }
        
        await server.withMethodHandler(CallTool.self) { params in
            switch params.name {
            case "get_status":
                return await self.performLocalHTTPRequest(path: "/health", queryItems: [])

            case "get_ui_context":
                let maxDepth = params.arguments?["max_depth"]?.intValue ?? 8
                let elementId = params.arguments?["element_id"]?.stringValue
                return await self.performLocalHTTPRequest(path: "/api/context", queryItems: [
                    URLQueryItem(name: "max_depth", value: "\(maxDepth)"),
                    URLQueryItem(name: "element_id", value: elementId)
                ])

            case "get_hierarchy":
                let maxDepth = params.arguments?["max_depth"]?.intValue ?? -1
                let filterClass = params.arguments?["filter_class"]?.stringValue
                let elementId = params.arguments?["element_id"]?.stringValue
                return await self.performLocalHTTPRequest(path: "/api/hierarchy", queryItems: [
                    URLQueryItem(name: "max_depth", value: "\(maxDepth)"),
                    URLQueryItem(name: "filter_class", value: filterClass),
                    URLQueryItem(name: "element_id", value: elementId)
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

            case "export_all_images":
                guard let directory = params.arguments?["directory"]?.stringValue else {
                    return .init(content: [.text("Missing directory")], isError: true)
                }
                return await self.performLocalHTTPRequest(
                    path: "/api/images/export",
                    queryItems: [],
                    method: "POST",
                    jsonBody: ["directory": directory]
                )
                
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
                guard let directory = params.arguments?["directory"]?.stringValue else {
                    return .init(content: [.text("Missing directory parameter. Please provide a valid directory path to save the screenshot.")], isError: true)
                }
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

            case "capture_ui_context":
                guard let directory = params.arguments?["directory"]?.stringValue else {
                    return .init(content: [.text("Missing directory")], isError: true)
                }
                return await self.captureUIContext(
                    directory: directory,
                    elementId: params.arguments?["element_id"]?.stringValue,
                    maxDepth: params.arguments?["max_depth"]?.intValue ?? 8,
                    refresh: params.arguments?["refresh"]?.boolValue ?? true
                )
                
            default:
                return .init(content: [.text("Unknown tool: \(params.name)")], isError: true)
            }
        }
    }

    private func captureUIContext(
        directory: String,
        elementId: String?,
        maxDepth: Int,
        refresh: Bool
    ) async -> CallTool.Result {
        do {
            if refresh {
                let reloadResult = await fetchLocalHTTP(
                    path: "/api/reload", queryItems: [], method: "POST"
                )
                if case .failure(let error) = reloadResult {
                    return .init(content: [.text("Reload failed: \(error.localizedDescription)")], isError: true)
                }
            }

            let contextResult = await fetchLocalHTTP(path: "/api/context", queryItems: [
                URLQueryItem(name: "max_depth", value: "\(maxDepth)"),
                URLQueryItem(name: "element_id", value: elementId)
            ])
            let contextData: Data
            switch contextResult {
            case .success(let data):
                contextData = data
            case .failure(let error):
                return .init(content: [.text("Context fetch failed: \(error.localizedDescription)")], isError: true)
            }

            guard let context = try JSONSerialization.jsonObject(with: contextData) as? [String: Any],
                  context["status"] as? String == "success" else {
                let text = String(data: contextData, encoding: .utf8) ?? "Invalid context response"
                return .init(content: [.text(text)], isError: true)
            }

            let targetId = elementId ?? context["screenshot_element_id"] as? String
            guard let targetId, !targetId.isEmpty else {
                return .init(content: [.text("No root element is available for capture")], isError: true)
            }

            let outputURL = URL(fileURLWithPath: directory).standardizedFileURL
            try FileManager.default.createDirectory(
                at: outputURL, withIntermediateDirectories: true
            )

            let contextURL = outputURL.appendingPathComponent("context.json")
            let normalizedContextData = try JSONSerialization.data(
                withJSONObject: context, options: [.prettyPrinted, .sortedKeys]
            )
            try normalizedContextData.write(to: contextURL)

            let elementResult = await fetchLocalHTTP(
                path: "/api/element/\(targetId)", queryItems: []
            )
            let elementURL = outputURL.appendingPathComponent("element.json")
            if case .success(let data) = elementResult,
               let object = try? JSONSerialization.jsonObject(with: data),
               let normalized = try? JSONSerialization.data(
                   withJSONObject: object, options: [.prettyPrinted, .sortedKeys]
               ) {
                try normalized.write(to: elementURL)
            }

            let screenshotResult = await fetchLocalHTTP(
                path: "/api/element/\(targetId)/screenshot", queryItems: []
            )
            let screenshotData: Data
            switch screenshotResult {
            case .success(let data):
                guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      payload["status"] as? String == "success",
                      let encoded = payload["data"] as? String,
                      let decoded = Data(base64Encoded: encoded) else {
                    let text = String(data: data, encoding: .utf8) ?? "Invalid screenshot response"
                    return .init(content: [.text(text)], isError: true)
                }
                screenshotData = decoded
            case .failure(let error):
                return .init(content: [.text("Screenshot fetch failed: \(error.localizedDescription)")], isError: true)
            }

            let screenshotURL = outputURL.appendingPathComponent("screenshot.png")
            try screenshotData.write(to: screenshotURL)

            var files = [
                "context": contextURL.path,
                "screenshot": screenshotURL.path
            ]
            if FileManager.default.fileExists(atPath: elementURL.path) {
                files["element"] = elementURL.path
            }
            let manifestURL = outputURL.appendingPathComponent("manifest.json")
            let manifest: [String: Any] = [
                "schema_version": 1,
                "captured_at": ISO8601DateFormatter().string(from: Date()),
                "server_url": apiServerURL,
                "target_element_id": targetId,
                "max_depth": maxDepth,
                "refreshed": refresh,
                "files": files
            ]
            let manifestData = try JSONSerialization.data(
                withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]
            )
            try manifestData.write(to: manifestURL)
            files["manifest"] = manifestURL.path

            let response: [String: Any] = [
                "status": "success",
                "target_element_id": targetId,
                "files": files
            ]
            let responseData = try JSONSerialization.data(
                withJSONObject: response, options: [.prettyPrinted, .sortedKeys]
            )
            return .init(
                content: [.text(String(data: responseData, encoding: .utf8) ?? "")],
                isError: false
            )
        } catch {
            return .init(content: [.text("Capture failed: \(error.localizedDescription)")], isError: true)
        }
    }
    
    private func fetchLocalHTTP(
        path: String,
        queryItems: [URLQueryItem],
        method: String = "GET",
        jsonBody: [String: Any]? = nil
    ) async -> Result<Data, Error> {
        var components = URLComponents(string: "\(apiServerURL)\(path)")!
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
        if let jsonBody {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            } catch {
                return .failure(error)
            }
        }
        
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
    
    private func performLocalHTTPRequest(
        path: String,
        queryItems: [URLQueryItem],
        method: String = "GET",
        jsonBody: [String: Any]? = nil
    ) async -> CallTool.Result {
        let result = await fetchLocalHTTP(
            path: path, queryItems: queryItems, method: method, jsonBody: jsonBody
        )
        switch result {
        case .success(let data):
            if let text = String(data: data, encoding: .utf8) {
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let isError = json?["status"] as? String == "error" || json?["error"] != nil
                return .init(content: [.text(text)], isError: isError)
            } else {
                return .init(content: [.text("Failed to decode response")], isError: true)
            }
        case .failure(let error):
            return .init(content: [.text("Request failed: \(error.localizedDescription)")], isError: true)
        }
    }
}
