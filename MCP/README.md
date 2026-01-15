# Lookin MCP 集成

这个目录包含了 Lookin 的 MCP (Model Context Protocol) 集成实现，允许通过 MCP 协议访问 Lookin 的视图调试功能。

## 功能特性

### 1. 获取视图层级 (get_hierarchy)
获取当前页面的完整视图层级结构，包括：
- 元素类名 (className)
- 布局信息 (frame)
- 可见性 (isHidden, alpha)
- 层级关系 (children)

**参数：**
- `max_depth`: 最大层级深度（可选，默认 -1 表示无限制）
- `filter_class`: 按类名过滤（可选）

### 2. 获取元素详细信息 (get_element_info)
获取指定元素的详细属性信息，包括：
- 基本信息（类名、标题）
- 布局信息（frame、bounds）
- 可见性和交互属性
- 父子关系

**参数：**
- `element_id`: 元素的唯一标识符 (oid)

### 3. 获取相对位置 (get_relative_position)
计算两个元素之间的相对位置关系，包括：
- 水平关系（左侧、右侧、重叠）
- 垂直关系（上方、下方、重叠）
- 距离信息
- 重叠区域

**参数：**
- `element_id_1`: 第一个元素的 OID
- `element_id_2`: 第二个元素的 OID

### 4. 刷新视图 (reload_view)
触发视图层级刷新，重新获取最新的界面状态。相当于点击 Lookin 的 Reload 按钮。

### 5. 搜索元素 (search_elements)
根据关键词搜索元素，支持多种搜索类型：
- `all`: 搜索所有字段
- `class`: 仅搜索类名
- `text`: 仅搜索文本内容
- `identifier`: 仅搜索标识符

**参数：**
- `query`: 搜索关键词
- `search_type`: 搜索类型（可选，默认 "all"）

### 6. 修改元素属性 (modify_element_attribute)
修改指定元素的属性值，例如：
- frame（位置和大小）
- backgroundColor（背景色）
- alpha（透明度）
- 其他可修改的属性

**参数：**
- `element_id`: 元素的 OID
- `attribute`: 属性名称
- `value`: 新的属性值

## 架构设计

```
┌─────────────────┐
│   MCP Client    │  (AI Assistant / IDE)
└────────┬────────┘
         │ MCP Protocol
         │
┌────────▼────────┐
│  MCP Server     │  (Python, lookin_mcp_server.py)
│  (stdio)        │
└────────┬────────┘
         │ JSON-RPC / HTTP
         │
┌────────▼────────┐
│  LKMCPBridge    │  (Objective-C)
│  (桥接层)        │
└────────┬────────┘
         │
┌────────▼────────┐
│  Lookin Client  │  (macOS App)
│  - Hierarchy    │
│  - Dashboard    │
│  - Connection   │
└─────────────────┘
```

## 文件说明

### lookin_mcp_server.py
Python 实现的 MCP 服务器，负责：
- 定义 MCP 工具接口
- 处理 MCP 协议通信
- 与 LKMCPBridge 交互

### LKMCPBridge.h / LKMCPBridge.m
Objective-C 桥接层，负责：
- 从 Lookin 数据源提取信息
- 将数据转换为 JSON 格式
- 执行视图操作（刷新、修改属性等）
- 管理 MCP 服务器进程

### requirements.txt
Python 依赖包列表

### mcp_config.json
MCP 服务器配置文件示例

## 安装和使用

### 1. 安装 Python 依赖

```bash
cd MCP
pip install -r requirements.txt
```

### 2. 集成到 Lookin 项目

在 Lookin 项目中添加 MCP 文件：

1. 将 `LKMCPBridge.h` 和 `LKMCPBridge.m` 添加到 Xcode 项目
2. 在需要使用 MCP 功能的地方导入头文件：

```objective-c
#import "LKMCPBridge.h"
```

### 3. 启动 MCP 服务器

在 Lookin 应用启动时或需要时启动 MCP 服务器：

```objective-c
[[LKMCPBridge sharedInstance] startMCPServer];
```

### 4. 配置 MCP 客户端

在你的 AI Assistant 或 IDE 中配置 MCP 服务器：

```json
{
  "mcpServers": {
    "lookin": {
      "command": "python3",
      "args": ["/path/to/Lookin/MCP/lookin_mcp_server.py"],
      "env": {}
    }
  }
}
```

### 5. 使用示例

通过 MCP 客户端调用工具：

```python
# 获取视图层级
hierarchy = mcp_client.call_tool("get_hierarchy", {
    "max_depth": 3,
    "filter_class": "UILabel"
})

# 获取元素详细信息
element_info = mcp_client.call_tool("get_element_info", {
    "element_id": "0x1234567890"
})

# 刷新视图
reload_result = mcp_client.call_tool("reload_view", {})

# 搜索元素
search_results = mcp_client.call_tool("search_elements", {
    "query": "登录",
    "search_type": "text"
})
```

## 开发计划

### 当前状态
- ✅ MCP 服务器框架
- ✅ 桥接层基础实现
- ✅ 数据导出功能
- ✅ 搜索功能
- ⚠️ 服务器进程管理（需要完善）
- ⚠️ 属性修改功能（需要完善）

### 待实现功能
- [ ] MCP 服务器与桥接层的通信机制
- [ ] 完整的属性修改支持
- [ ] 截图导出功能
- [ ] 实时监听视图变化
- [ ] 性能优化
- [ ] 错误处理和日志

## 技术细节

### 数据流

1. **获取数据流程：**
   ```
   MCP Client → MCP Server → LKMCPBridge → LKStaticHierarchyDataSource → LookinHierarchyInfo
   ```

2. **修改数据流程：**
   ```
   MCP Client → MCP Server → LKMCPBridge → LKInspectableApp → iOS Device
   ```

### 关键类和方法

- `LKStaticHierarchyDataSource`: 管理视图层级数据
- `LookinHierarchyInfo`: 存储完整的层级信息
- `LookinDisplayItem`: 表示单个视图元素
- `LKInspectableApp`: 管理与 iOS 设备的连接
- `LKAppsManager`: 管理当前正在检查的应用

## 注意事项

1. **线程安全**: 所有对 Lookin 数据的访问都应该在主线程进行
2. **数据同步**: MCP 服务器返回的是快照数据，需要手动刷新
3. **性能考虑**: 大型视图层级可能导致 JSON 数据量较大
4. **错误处理**: 需要妥善处理连接断开、数据不可用等情况

## 贡献

欢迎提交 Issue 和 Pull Request 来改进 MCP 集成功能。

## 许可证

遵循 Lookin 项目的 GPL-3.0 许可证。
