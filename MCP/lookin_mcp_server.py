#!/usr/bin/env python3
"""
Lookin MCP Server
提供 Lookin 视图调试功能的 MCP 接口
"""

import asyncio
import json
import logging
from typing import Any, Optional
from mcp.server import Server
from mcp.types import Tool, TextContent, ImageContent, EmbeddedResource
import mcp.server.stdio
import aiohttp

# 配置日志
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("lookin-mcp-server")

# 创建 MCP 服务器实例
app = Server("lookin-mcp-server")

# Lookin HTTP 服务器地址
LOOKIN_SERVER_URL = "http://localhost:10086"

# 存储 Lookin 连接状态
lookin_state = {
    "connected": False,
    "hierarchy": None,
    "selected_items": []
}


@app.list_tools()
async def list_tools() -> list[Tool]:
    """列出所有可用的工具"""
    return [
        Tool(
            name="get_hierarchy",
            description="获取当前页面的视图层级结构，包含所有元素的基本信息（类名、frame、是否可见等）",
            inputSchema={
                "type": "object",
                "properties": {
                    "max_depth": {
                        "type": "integer",
                        "description": "最大层级深度，默认为 -1（无限制）",
                        "default": -1
                    },
                    "filter_class": {
                        "type": "string",
                        "description": "可选：按类名过滤视图，例如 'UILabel' 或 'UIButton'"
                    }
                }
            }
        ),
        Tool(
            name="get_element_info",
            description="获取指定元素的详细信息，包括所有属性、约束、子视图等",
            inputSchema={
                "type": "object",
                "properties": {
                    "element_id": {
                        "type": "string",
                        "description": "元素的唯一标识符（oid）"
                    }
                },
                "required": ["element_id"]
            }
        ),
        Tool(
            name="get_relative_position",
            description="获取两个元素之间的相对位置关系",
            inputSchema={
                "type": "object",
                "properties": {
                    "element_id_1": {
                        "type": "string",
                        "description": "第一个元素的唯一标识符"
                    },
                    "element_id_2": {
                        "type": "string",
                        "description": "第二个元素的唯一标识符"
                    }
                },
                "required": ["element_id_1", "element_id_2"]
            }
        ),
        Tool(
            name="reload_view",
            description="刷新视图层级，重新获取最新的界面状态",
            inputSchema={
                "type": "object",
                "properties": {}
            }
        ),
        Tool(
            name="search_elements",
            description="搜索包含指定文本或类名的元素",
            inputSchema={
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "搜索关键词，可以是类名、文本内容或标识符"
                    },
                    "search_type": {
                        "type": "string",
                        "enum": ["all", "class", "text", "identifier", "size"],
                        "description": "搜索类型：all（全部）、class（类名）、text（文本）、identifier（标识符）、size（尺寸，格式如 100x200）",
                        "default": "all"
                    }
                },
                "required": ["query"]
            }
        ),
        Tool(
            name="modify_element_attribute",
            description="修改元素的属性值（例如 frame、backgroundColor、alpha 等）",
            inputSchema={
                "type": "object",
                "properties": {
                    "element_id": {
                        "type": "string",
                        "description": "元素的唯一标识符"
                    },
                    "attribute": {
                        "type": "string",
                        "description": "要修改的属性名称"
                    },
                    "value": {
                        "type": "string",
                        "description": "新的属性值"
                    }
                },
                "required": ["element_id", "attribute", "value"]
            }
        ),
        Tool(
            name="save_image",
            description="将指定元素的图片将会保存到本地目录（默认为当前目录）",
            inputSchema={
                "type": "object",
                "properties": {
                    "element_id": {
                        "type": "string",
                        "description": "元素的唯一标识符"
                    },
                    "directory": {
                        "type": "string",
                        "description": "保存图片的目录路径，默认为当前工作目录"
                    },
                    "filename": {
                        "type": "string",
                        "description": "保存的文件名，默认为 element_{oid}.png"
                    }
                },
                "required": ["element_id"]
            }
        )
    ]


@app.call_tool()
async def call_tool(name: str, arguments: Any) -> list[TextContent]:
    """处理工具调用"""
    
    try:
        if name == "get_hierarchy":
            return await get_hierarchy(arguments)
        elif name == "get_element_info":
            return await get_element_info(arguments)
        elif name == "get_relative_position":
            return await get_relative_position(arguments)
        elif name == "reload_view":
            return await reload_view(arguments)
        elif name == "search_elements":
            return await search_elements(arguments)
        elif name == "modify_element_attribute":
            return await modify_element_attribute(arguments)

        elif name == "save_image":
            return await save_image(arguments)
        else:
            return [TextContent(
                type="text",
                text=f"未知的工具: {name}"
            )]
    except Exception as e:
        logger.error(f"工具调用失败: {name}, 错误: {str(e)}")
        return [TextContent(
            type="text",
            text=f"错误: {str(e)}"
        )]


async def get_hierarchy(arguments: dict) -> list[TextContent]:
    """获取视图层级结构"""
    max_depth = arguments.get("max_depth", -1)
    filter_class = arguments.get("filter_class")
    
    try:
        params = {"max_depth": max_depth}
        if filter_class:
            params["filter_class"] = filter_class
            
        async with aiohttp.ClientSession() as session:
            async with session.get(f"{LOOKIN_SERVER_URL}/api/hierarchy", params=params) as resp:
                if resp.status == 200:
                    result = await resp.json()
                    return [TextContent(
                        type="text",
                        text=json.dumps(result, indent=2, ensure_ascii=False)
                    )]
                else:
                    error_text = await resp.text()
                    return [TextContent(
                        type="text",
                        text=json.dumps({
                            "status": "error",
                            "message": f"HTTP {resp.status}: {error_text}"
                        }, indent=2, ensure_ascii=False)
                    )]
    except aiohttp.ClientConnectorError:
        return [TextContent(
            type="text",
            text=json.dumps({
                "status": "error",
                "message": "无法连接到 Lookin 服务器。请确保 Lookin 应用正在运行。"
            }, indent=2, ensure_ascii=False)
        )]
    except Exception as e:
        return [TextContent(
            type="text",
            text=json.dumps({
                "status": "error",
                "message": f"请求失败: {str(e)}"
            }, indent=2, ensure_ascii=False)
        )]


async def get_element_info(arguments: dict) -> list[TextContent]:
    """获取元素详细信息"""
    element_id = arguments["element_id"]
    
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(f"{LOOKIN_SERVER_URL}/api/element/{element_id}") as resp:
                if resp.status == 200:
                    result = await resp.json()
                    return [TextContent(
                        type="text",
                        text=json.dumps(result, indent=2, ensure_ascii=False)
                    )]
                else:
                    error_text = await resp.text()
                    return [TextContent(
                        type="text",
                        text=json.dumps({
                            "status": "error",
                            "message": f"HTTP {resp.status}: {error_text}"
                        }, indent=2, ensure_ascii=False)
                    )]
    except Exception as e:
        return [TextContent(
            type="text",
            text=json.dumps({
                "status": "error",
                "message": f"请求失败: {str(e)}"
            }, indent=2, ensure_ascii=False)
        )]


async def get_relative_position(arguments: dict) -> list[TextContent]:
    """获取两个元素的相对位置"""
    element_id_1 = arguments["element_id_1"]
    element_id_2 = arguments["element_id_2"]
    
    try:
        params = {
            "element_id_1": element_id_1,
            "element_id_2": element_id_2
        }
        async with aiohttp.ClientSession() as session:
            async with session.get(f"{LOOKIN_SERVER_URL}/api/relative_position", params=params) as resp:
                if resp.status == 200:
                    result = await resp.json()
                    return [TextContent(
                        type="text",
                        text=json.dumps(result, indent=2, ensure_ascii=False)
                    )]
                else:
                    error_text = await resp.text()
                    return [TextContent(
                        type="text",
                        text=json.dumps({
                            "status": "error",
                            "message": f"HTTP {resp.status}: {error_text}"
                        }, indent=2, ensure_ascii=False)
                    )]
    except Exception as e:
        return [TextContent(
            type="text",
            text=json.dumps({
                "status": "error",
                "message": f"请求失败: {str(e)}"
            }, indent=2, ensure_ascii=False)
        )]


async def reload_view(arguments: dict) -> list[TextContent]:
    """刷新视图"""
    
    try:
        async with aiohttp.ClientSession() as session:
            async with session.post(f"{LOOKIN_SERVER_URL}/api/reload") as resp:
                if resp.status == 200:
                    result = await resp.json()
                    return [TextContent(
                        type="text",
                        text=json.dumps(result, indent=2, ensure_ascii=False)
                    )]
                else:
                    error_text = await resp.text()
                    return [TextContent(
                        type="text",
                        text=json.dumps({
                            "status": "error",
                            "message": f"HTTP {resp.status}: {error_text}"
                        }, indent=2, ensure_ascii=False)
                    )]
    except Exception as e:
        return [TextContent(
            type="text",
            text=json.dumps({
                "status": "error",
                "message": f"请求失败: {str(e)}"
            }, indent=2, ensure_ascii=False)
        )]


async def search_elements(arguments: dict) -> list[TextContent]:
    """搜索元素"""
    query = arguments["query"]
    search_type = arguments.get("search_type", "all")
    
    try:
        params = {
            "query": query,
            "search_type": search_type
        }
        async with aiohttp.ClientSession() as session:
            async with session.get(f"{LOOKIN_SERVER_URL}/api/search", params=params) as resp:
                if resp.status == 200:
                    result = await resp.json()
                    return [TextContent(
                        type="text",
                        text=json.dumps(result, indent=2, ensure_ascii=False)
                    )]
                else:
                    error_text = await resp.text()
                    return [TextContent(
                        type="text",
                        text=json.dumps({
                            "status": "error",
                            "message": f"HTTP {resp.status}: {error_text}"
                        }, indent=2, ensure_ascii=False)
                    )]
    except Exception as e:
        return [TextContent(
            type="text",
            text=json.dumps({
                "status": "error",
                "message": f"请求失败: {str(e)}"
            }, indent=2, ensure_ascii=False)
        )]


async def modify_element_attribute(arguments: dict) -> list[TextContent]:
    """修改元素属性"""
    element_id = arguments["element_id"]
    attribute = arguments["attribute"]
    value = arguments["value"]
    
    # 注意: 修改属性功能暂未在 HTTP 服务器中实现
    return [TextContent(
        type="text",
        text=json.dumps({
            "status": "error",
            "message": "修改元素属性功能暂未实现",
            "element_id": element_id,
            "attribute": attribute,
            "value": value
        }, indent=2, ensure_ascii=False)
    )]


async def save_image(arguments: dict) -> list[TextContent]:
    """保存图片"""
    element_id = arguments["element_id"]
    directory = arguments.get("directory", ".")
    filename = arguments.get("filename")
    
    import base64
    import os
    
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(f"{LOOKIN_SERVER_URL}/api/element/{element_id}/image") as resp:
                if resp.status == 200:
                    result = await resp.json()
                    status = result.get("status")
                    if status != "success":
                         return [TextContent(
                            type="text",
                            text=json.dumps({
                                "status": "error",
                                "message": result.get("message", "Unknown error")
                            }, indent=2, ensure_ascii=False)
                        )]

                    base64_data = result.get("data")
                    if not base64_data:
                         return [TextContent(
                            type="text",
                            text=json.dumps({
                                "status": "error",
                                "message": "No image data received"
                            }, indent=2, ensure_ascii=False)
                        )]
                    
                    # Ensure directory exists
                    if not os.path.exists(directory):
                        os.makedirs(directory)
                        
                    if not filename:
                        filename = f"element_{element_id}.png"
                        
                    file_path = os.path.join(directory, filename)
                    
                    try:
                        image_data = base64.b64decode(base64_data)
                        with open(file_path, "wb") as f:
                            f.write(image_data)
                            
                        return [TextContent(
                            type="text",
                            text=json.dumps({
                                "status": "success",
                                "message": f"Image saved to {os.path.abspath(file_path)}",
                                "path": os.path.abspath(file_path)
                            }, indent=2, ensure_ascii=False)
                        )]
                    except Exception as text_err:
                         return [TextContent(
                            type="text",
                            text=json.dumps({
                                "status": "error",
                                "message": f"Failed to save file: {str(text_err)}"
                            }, indent=2, ensure_ascii=False)
                        )]
                    
                else:
                    error_text = await resp.text()
                    return [TextContent(
                        type="text",
                        text=json.dumps({
                            "status": "error",
                            "message": f"HTTP {resp.status}: {error_text}"
                        }, indent=2, ensure_ascii=False)
                    )]
    except Exception as e:
        return [TextContent(
            type="text",
            text=json.dumps({
                "status": "error",
                "message": f"请求失败: {str(e)}"
            }, indent=2, ensure_ascii=False)
        )]


async def main():
    """启动 MCP 服务器"""
    async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
        logger.info("Lookin MCP Server 启动中...")
        await app.run(
            read_stream,
            write_stream,
            app.create_initialization_options()
        )


if __name__ == "__main__":
    asyncio.run(main())
