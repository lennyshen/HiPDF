# HiPDF 本地验证记录

验证时间：2026-09-06。环境：Apple Silicon / macOS 26.4.1 / Apple Swift 6.3。部署最低版本为 macOS 14，未在 macOS 14 真机或 Intel Mac 上测试。

## 已执行

- Release 构建成功：`swift build -c release -j 2`。
- 20 项集成测试通过，0 失败、0 跳过；最新完整运行 27.756 秒，命令为 `PYTHONPATH=engine <python> -m unittest discover -s tests -v`。
- 实際 PDF 输出使用 PyMuPDF、pypdf、python-docx、python-pptx、openpyxl 等独立读取方式验证，不以文件存在作为唯一标准。
- 验证原始输入 SHA-256 保持不变；验证页序、拆分、页面数量、旋转和裁剪尺寸。
- 验证压缩后保留文字且样本文件体积减小。
- 验证 AES-256 加密、错误密码失败、正确密码解密及不加密输出。
- 验证密文内容不可从输出提取，元数据和附件不保留测试敏感文字。
- 验证表单字段 `/V`、外观 `/AP`，并验证平面化后不再有交互字段。
- 使用真实栅格化的中英文扫描页验证 Vision OCR，提取结果含测试标题及收入数字。
- 验证 DOCX 可编辑文本、PPTX 幻灯片与文本框、XLSX 表格值，执行 Word/PPT/Excel → PDF。
- 执行 PDF/A 导出并检测 PDF/A 标记；没有将此检查宣称为完整标准一致性验证。
- 创建测试 PKCS#12 证书签名，独立验证签名 `intact` 和 `valid`。
- 使用本机 HTTP 模拟服务验证 `/v1/chat/completions`、Bearer 授权头、自定义模型、摘要与两种翻译方式；长文实际分为 6 段并归并，包含最后一段标记。
- 验证 HTTP 401 的明确错误、服务端错误不回显密钥、模型输出截断时失败。
- 在正在等待模型响应时向 worker 发送 SIGTERM，验证任务返回取消并清空临时目录。
- 在原生界面打开工作台、分类工具、文件选择器和 HTML 工具，检查界面视觉；HTML 通过本机测试服务导出为 7 页 PDF，原生预览显示成功，输出中存在 `FINAL_MARKER`。
- 最终应用安装到 `~/Applications/HiPDF.app`；使用安装包内置 Python 重跑上述 20 项测试，0 失败、0 跳过。
- Swift `EngineClient` → 内置 Python worker 桥接测试通过：Office/OCR 健康检查成功；压缩输出由 PDFKit 独立确认 3 页且包含原文数字 `158000`。
- 对整包 22,146 个常规文件执行实际逐字节读取，总量约 1,161 MB，读取错误为 0。原始包和安装副本均通过 `codesign --verify --deep --strict`。
- 最终安装后的原生应用可正常启动，工具首页显示 33 个入口；AI 设置界面可配置地址、API Key、模型及高级参数。
- 安装 ZIP 的全部 49,069 个条目通过 CRC 完整性检查，未发现损坏条目；发布文件 SHA-256 见 `SHA256SUMS.txt`。

## 未进行及适用限制

- 没有使用真实用户 API Key，也没有对特定外部 LLM 服务的翻译或摘要质量作验证；界面可自行配置并测试。
- 没有连接实体扫描仪，不能宣称硬件扫描已在当前环境实测成功。
- 没有执行完整 veraPDF 一致性审计，没有 Apple Developer ID 签名/公证，也没有官网云签署基础设施。
- 自动检测表单、复杂 Office 布局、扫描页 OCR 和保留版面翻译仍有内容相关的质量限制，详见 `FEATURES.md`。

测试样本全部由代码合成，不包含用户业务文档或实际凭证。


## 1.0.1 导入与预览修复（2026-09-06）

- 原版实际复现：本地三页 PDF 可由 PDFKit 读取并在“编辑 PDF”显示；OneDrive 中同类合成 PDF 为 `compressed,dataless` 占位文件，`PDFDocument(url:)` 返回 nil，原界面错误地只提示密码或换文件。
- 原版在导入文件队列和加载预览时均同步调用 PDFKit；1.0.1 去掉队列导入时的同步解析，后台使用 NSFileCoordinator 协调读取后再交给 PDFKit。
- 分别处理云盘未就绪、普通读取失败、空/损坏 PDF 和缺失/错误密码，支持重新加载、在 Finder 显示、切换文件时取消旧加载，读取等待最多 30 秒。
- `scripts/preview_smoke.swift` 验证了含中文和空格的大写扩展名路径、页数和可提取文字、加密文件的缺失/错误/正确密码、空/损坏/不存在的文件、加载取消和原件字节不变。实际 OneDrive 占位样本在有界时间内返回 unavailable，未误报密码或 PDF 格式问题。
- 原生 Release 编译及两个应用副本的深度签名校验通过。PDF 引擎未改动，前述 20 项引擎测试结果适用于相同引擎代码；此修复新增原生加载回归测试。

运行原生加载回归测试：

```sh
swiftc -parse-as-library Sources/HiPDF/PDFLoader.swift scripts/preview_smoke.swift -o /tmp/hipdf-preview-tests
/tmp/hipdf-preview-tests
```

测试工具自行生成临时样本并清理，可选传入一份已知的合成云盘占位 PDF 路径以验证实际 File Provider 失败路径。未使用用户业务文档内容。

- 1.0.1 原生界面实际完成本地三页样本导入、预览、框选添加 `HiPDF EDIT PREVIEW CHECK`、处理和结果预览；独立读取导出 PDF 确认 3 页，第一页存在新增文字、第二页无此新增文字，输入与测试前副本的 SHA-256 一致。
