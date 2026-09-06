# HiPDF for macOS

中文原生 PDF 工作空间。提供 33 个工具入口与本地工作流程；功能参考 [iLovePDF 中文站](https://www.ilovepdf.com/zh-cn)。采用独立界面与实现，具体能力和与官网的差异见 [功能覆盖表](docs/FEATURES.md)。

## 运行

当前版本为 1.0.1：PDF 预览后台协调读取云盘文件，分别提示云盘未就绪、读取失败、密码和 PDF 内容异常，支持重新加载及取消过期请求。

打开 `dist/HiPDF.app`，也可复制到自己的 `~/Applications`。应用包含 Python/PDF/Office 引擎，普通 PDF 操作不依赖网络或 Microsoft Office。macOS 14+，Apple Silicon；此构建不是 Intel 通用版本。

AI 功能在“设置 → AI 服务”配置 Base URL、模型和 API Key，兼容 OpenAI `/chat/completions`。Key 使用 macOS 钥匙串保存。本机免认证服务可留空 Key。完整操作说明见 `Resources/USER_GUIDE.html`。

此版本是本地临时签名构建，未进行 Apple Developer ID 签名和公证。对外分发需自行完成发布签名，并遵循 [开源组件许可](THIRD_PARTY_NOTICES.md)。

## 构建

需要 macOS、Swift 6 工具链（Command Line Tools）和 uv。

```sh
bash scripts/setup.sh
swift scripts/make_icon.swift Resources
iconutil -c icns Resources/HiPDF.iconset -o Resources/HiPDF.icns
bash scripts/build.sh --archive
```

`setup.sh` 创建项目虚拟环境，下载并校验 LibreOffice。`build.sh` 生成自包含的 `.app`，`--archive` 生成 ZIP。引擎与源码留在项目中，应用离开项目路径后仍可运行。

请在普通本地目录构建，例如 `~/Developer/HiPDF`。OneDrive/iCloud 等同步目录可能将运行时文件变成占位文件，影响编译、复制及签名。可用 `HIPDF_DIST_DIR="$HOME/HiPDF-Delivery" bash scripts/build.sh --archive` 指定本地输出目录。

## 开发与验证

```sh
swift build -j 2
PYTHONPATH=engine .venv/bin/python -m unittest discover -s tests -v
bash scripts/verify.sh
```

`Sources/HiPDF`：SwiftUI、PDFKit、WebKit、ImageKit 界面与进程桥接。
`Sources/HiPDFOCR`：Vision OCR 命令行辅助程序。
`engine`：PDF 处理、Office 转换、AI、任务隔离与工作流程。
`Resources/tools.json`：33 个工具的共享清单，由 `scripts/catalog.py` 生成。
`tests/test_engine.py`：合成文件集成测试和本机模拟 OpenAI 服务。

所有输出另存；普通任务不联网；LLM 文档文字只发给用户配置的服务。异常处理不回显服务端敏感正文。正式归档、签署和敏感文档处理的能力边界明确列在功能覆盖表中。
