# HiPDF 设计与实现计划

**目标：** 参照 iLovePDF 中文官网的 33 项 PDF 工具与工作流程，构建可在 Apple Silicon Mac 本地运行的中文 HiPDF 应用，AI 使用用户配置的 OpenAI 兼容服务。

**架构：** SwiftUI 原生窗口、PDFKit 预览与页面选择；Python 子进程按任务隔离执行 PDF、Office、AI 操作；Vision 离线 OCR；LibreOffice 用于 Office 导入与 PDF/A。所有结果另存到独立任务目录。API Key 存于 macOS 钥匙串，仅通过 stdin 传给任务进程。

**技术栈：** Swift 5.9+ / macOS 14+，PDFKit、Vision、ImageKit、WebKit，PyMuPDF、pypdf、python-docx、python-pptx、openpyxl、pdf2docx、pyHanko、LibreOffice。

---

## 设计选择

1. 采用 SwiftUI 原生应用：直接使用 macOS PDF 预览、拖放、菜单、文件选择器和钥匙串，应用无常驻 HTTP 服务。
2. Electron 可共用网页组件，但会增加浏览器运行时、IPC 与文件权限管理，本项目无需跨平台。
3. 纯 Swift 依赖较少，但 Office 重建、PDF 表格提取与数字签名成熟库较少，因此采用隔离 Python 引擎补足。

## 产品结构

左侧：工作台、收藏、分类、工作流程、最近任务、设置。主区：搜索、常用工具、完整功能卡片。工具工作区：输入文件队列、PDF 预览与缩略图、参数面板、运行/取消、输出结果与 Finder 定位。编辑/裁剪/密文/签名支持在预览上框选位置，页面顺序支持缩略图选择与显式序列。设置显示本地引擎状态并提供 LLM 连通测试。

## 实施任务与文件

1. `docs/FEATURES.md`：记录当前官方页面、33 项对应工具、验收依据和边界；持续更新实测结果。
2. `engine/worker.py`、`engine/pdf_ops.py`：NDJSON 进度、输入验证、任务隔离、合并拆分/排列、图片、压缩、安全与编辑；写 `tests/test_engine.py` 验证页序、原件完整性、密文无法提取、密码及取消失败清理。
3. `engine/converters.py`：Office 导入导出、PDF/A、OCR、Markdown、比较；`Sources/HiPDFOCR/main.swift` 实现 Vision OCR。验证输出实际能被各格式解析器打开且内容存在。
4. `engine/ai.py`：OpenAI Chat Completions、分块摘要及归并、逐块/版面翻译、明确失败及超时。使用本地模拟 API 验证端点、Authorization、长文无静默截断、HTTP 错误，不依赖真实密钥。
5. `Sources/HiPDF/{Models,Engine,App,Dashboard,Workbench,PDFPreview,Settings,Scanner}.swift`：原生界面、任务取消、拖放、页面区域编辑、钥匙串和工作流程。`swift build` 验证后运行真机界面检查。
6. `scripts/{setup,build,verify}.sh`：安装项目独立运行时、构建 .app 和可分发压缩包；保留构建说明、依赖版本及许可证。
7. 用生成的中英文 PDF、扫描件、表格、DOCX/PPTX/XLSX 和本地 HTTP 模拟服务执行集成测试，打开应用检查搜索、选文件、运行结果、设置。

## 验收与边界

工具入口必须关联真实操作，禁止未实现操作返回成功。非 AI PDF 操作不联网；网页 URL 导入和用户启动的 AI 操作按其目的联网。输出保留原文件；密码、API Key 不写入任务历史/命令行/诊断。扫描硬件及远程签署属于外部能力：实现 macOS 扫描设备接入、本地签名和证书签名；不能把离线文件交换宣称为带邮件邀请、身份核验、审计时间戳的签署 SaaS。翻译尽量保持文字块与图片位置，对无法容纳的文本明确报告；Office 往返重建不承诺像素级还原。PDF/A 输出通过合规工具验证才宣称符合某一标准。
