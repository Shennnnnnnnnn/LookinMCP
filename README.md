![Preview](https://cdn.lookin.work/public/style/images/independent/homepage/preview_en_1x.jpg "Preview")

# Introduction
You can inspect and modify views in iOS app via Lookin, just like UI Inspector in Xcode, or another app called Reveal.

Official Website：https://lookin.work/

# Integration Guide
To use Lookin macOS app, you need to integrate LookinServer (iOS Framework of Lookin) into your iOS project.

> **Warning**
Never integrate LookinServer in Release building configuration.

## via CocoaPods:
### Swift Project
`pod 'LookinServer', :subspecs => ['Swift'], :configurations => ['Debug']`
### Objective-C Project
`pod 'LookinServer', :configurations => ['Debug']`
## via Swift Package Manager:
`https://github.com/QMUI/LookinServer/`

# Repository
LookinServer: https://github.com/QMUI/LookinServer

macOS app: https://github.com/hughkli/Lookin/

# Tips
- How to display custom information in Lookin: https://bytedance.larkoffice.com/docx/TRridRXeUoErMTxs94bcnGchnlb
- How to display more member variables in Lookin: https://bytedance.larkoffice.com/docx/CKRndHqdeoub11xSqUZcMlFhnWe
- How to turn on Swift optimization for Lookin: https://bytedance.larkoffice.com/docx/GFRLdzpeKoakeyxvwgCcZ5XdnTb
- Documentation Collection: https://bytedance.larkoffice.com/docx/Yvv1d57XQoe5l0xZ0ZRc0ILfnWb

# XML Export Feature
Lookin now supports exporting UI hierarchy to XML format, which includes all necessary layout information for WebApp development.

## Features
- Export complete UI hierarchy with frame, colors, corner radius, and other properties
- Smaller file size compared to .lookin format (no screenshots)
- Human-readable XML format
- Ready for WebApp reconstruction

## Usage
1. Open your app in Lookin
2. Select `File` -> `Export`
3. Choose `Export Format: XML`
4. Save the file

## Documentation
- [XML Export Guide](Docs/XML导出功能说明.md)
- [HTML Demo](Docs/XML_to_WebApp_Demo.html)
- [React Example](Docs/React_Component_Example.jsx)
- [Vue Example](Docs/Vue_Component_Example.vue)
- [XML Example](Docs/XML_Export_Example.xml)

# AI Integration

Lookin can expose the currently inspected iOS interface to AI tools through native MCP, a local CLI, and a repository Skill. Enable **AI Integration** in Settings, then use the workflow documented in [MCP/README.md](MCP/README.md).

For UI reproduction, create a synchronized screenshot and hierarchy bundle:

```bash
./bin/lookin capture --output .lookin-capture
```

# Acknowledgements
https://qxh1ndiez2w.feishu.cn/docx/YIFjdE4gIolp3hxn1tGckiBxnWf

---
# 简介
Lookin 可以查看与修改 iOS App 里的 UI 对象，类似于 Xcode 自带的 UI Inspector 工具，或另一款叫做 Reveal 的软件。

官网：https://lookin.work/

# 安装 LookinServer Framework
如果这是你的 iOS 项目第一次使用 Lookin，则需要先把 LookinServer 这款 iOS Framework 集成到你的 iOS 项目中。

> **Warning**
记得不要在 AppStore 模式下集成 LookinServer。

## 通过 CocoaPods：

### Swift 项目
`pod 'LookinServer', :subspecs => ['Swift'], :configurations => ['Debug']`
### Objective-C 项目
`pod 'LookinServer', :configurations => ['Debug']`

## 通过 Swift Package Manager:
`https://github.com/QMUI/LookinServer/`

# 源代码仓库

iOS 端 LookinServer：https://github.com/QMUI/LookinServer

macOS 端软件：https://github.com/hughkli/Lookin/

# 技巧
- 如何在 Lookin 中展示自定义信息: https://bytedance.larkoffice.com/docx/TRridRXeUoErMTxs94bcnGchnlb
- 如何在 Lookin 中展示更多成员变量: https://bytedance.larkoffice.com/docx/CKRndHqdeoub11xSqUZcMlFhnWe
- 如何为 Lookin 开启 Swift 优化: https://bytedance.larkoffice.com/docx/GFRLdzpeKoakeyxvwgCcZ5XdnTb
- 文档汇总：https://bytedance.larkoffice.com/docx/Yvv1d57XQoe5l0xZ0ZRc0ILfnWb

# XML 导出功能
Lookin 现在支持将 UI 层级结构导出为 XML 格式，包含所有必要的布局信息，可用于 WebApp 页面搭建。

## 功能特性
- 导出完整的 UI 层级，包含 frame、颜色、圆角等所有属性
- 文件体积更小（不包含截图数据）
- 人类可读的 XML 格式
- 可直接用于 WebApp 页面重建

## 使用方法
1. 在 Lookin 中打开你的应用
2. 选择 `File` -> `Export`
3. 选择 `Export Format: XML`
4. 保存文件

## 文档资料
- [XML 导出功能说明](Docs/XML导出功能说明.md)
- [HTML 演示工具](Docs/XML_to_WebApp_Demo.html)
- [React 组件示例](Docs/React_Component_Example.jsx)
- [Vue 组件示例](Docs/Vue_Component_Example.vue)
- [XML 示例文件](Docs/XML_Export_Example.xml)

# AI 集成

Lookin 可通过原生 MCP、本地 CLI 和仓库级 Skill 将当前正在检查的 iOS 界面提供给 AI 工具。在设置中开启 **AI Integration** 后，按照 [MCP 使用说明](MCP/README.md) 接入。

进行 UI 复刻时，建议一次性生成同步的截图与层级数据：

```bash
./bin/lookin capture --output .lookin-capture
```

# 鸣谢
https://qxh1ndiez2w.feishu.cn/docx/YIFjdE4gIolp3hxn1tGckiBxnWf
