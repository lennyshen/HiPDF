# HiPDF 功能覆盖与研究记录

研究日期：2026-09-05。目标平台：macOS 14+，Apple Silicon。此文件区分实现能力与外部服务，不能把拥有同名入口视为与商业服务完全等价。

官方参考：[中文工具总览](https://www.ilovepdf.com/zh-cn)、[PDF 表单](https://www.ilovepdf.com/zh-cn/pdf-forms)、[AI 摘要](https://www.ilovepdf.com/zh-cn/pdf-summarize)、[PDF 翻译](https://www.ilovepdf.com/zh-cn/translate-pdf)、[签名](https://www.ilovepdf.com/zh-cn/sign-pdf)。官网工具总览包含 33 个独立入口和工作流程；工作流程详情需要登录，未登录私有账户。

## 逐项实现

| 官网能力 | HiPDF 操作 | 实现与实际边界 |
|---|---|---|
| 合并 PDF | merge | 队列顺序合并、书签层级、保留表单 |
| 拆分 PDF | split | 每页、连续区间、每 N 页；严格验证页码 |
| 删除页面 | delete | 删除所选页面，禁止删除全部 |
| 提取页面 | extract | 按范围提取，另存文件 |
| 排列 PDF | organize | 自定义顺序、倒序、重复页；跨文件先合并 |
| 扫描为 PDF | scan | macOS 扫描仪入口、照片/多页 TIFF 导入、灰度/黑白增强；硬件能力需要实际设备 |
| 压缩 PDF | compress | 无损对象压缩、图片降采样/重编码，保留文字层；不能保证所有文件变小 |
| 修复 PDF | repair | 重建能读取的对象和交叉引用；不保证恢复缺失内容 |
| OCR PDF | ocr | Vision 离线识别并叠加不可见文字层，默认跳过已有文字页 |
| JPG 转 PDF | imageToPDF | JPG/PNG/TIFF/BMP/WebP，EXIF 校正、纸张、方向和边距 |
| Word 转 PDF | wordToPDF | LibreOffice 转换 DOC/DOCX/ODT/RTF |
| PowerPoint 转 PDF | pptToPDF | LibreOffice 转换 PPT/PPTX/ODP |
| Excel 转 PDF | excelToPDF | XLS/XLSX/ODS/CSV，按工作簿打印设置 |
| HTML 转 PDF | htmlToPDF | WebKit 加载本地 HTML 或 URL，按纸张分页；登录态网页受限 |
| PDF 转 JPG | pdfToImage | JPG/PNG，36–600 DPI，支持提取嵌入图片 |
| PDF 转 Word | pdfToWord | 重建可编辑段落和表格；复杂多栏与字体需校对 |
| PDF 转 PowerPoint | pdfToPPT | 图形背景加可编辑文字框，或整页图片模式 |
| PDF 转 Excel | pdfToExcel | 结构化表格独立 sheet；无表格时明确回退至文字行 |
| PDF 转 PDF/A | pdfa | LibreOffice PDF/A-2b 导出；元数据检测不等同于完整合规验证，正式归档需 veraPDF |
| 旋转 PDF | rotate | 指定页旋转 90/180/270 度 |
| 添加页码 | numbers | 顶部/底部、自定义起始编号、页码模板 |
| 添加水印 | watermark | 文字/图片、位置、字号、透明度与颜色 |
| 裁剪 PDF | crop | 预览框选、四边裁剪、应用至所选页面；只改变可见范围 |
| 编辑 PDF | edit | 添加文字、图片、矩形、高亮、手写；支持多个选区，不改写原有段落 |
| PDF 表单 | forms | 创建/填写文本、复选、单选与列表字段，边框启发式自动检测，可选平面化 |
| PDF 解锁 | unlock | 正确密码验证后另存不加密版本，不做密码破解 |
| PDF 加密 | encrypt | AES-256 打开密码、打印与复制权限 |
| PDF 签名 | sign | 输入/图片/手写视觉签名，PKCS#12 加密证书签名；不提供云端邀请、可信时间戳及身份核验 |
| 标记密文 | redact | 删除真实文字与图像区域，清理附件、隐藏层、元数据，重写输出；需用户复核敏感区域完整性 |
| 比较 PDF | compare | 并排 PDF、文字增删颜色标记、逐行 HTML 报告、检测视觉变化 |
| AI 摘要 | summarize | 自选语言/长短、长文分段与归并，自动本地 OCR，输出 Markdown + PDF |
| PDF 翻译 | translate | 逐文字块保留版面，或完整译文重新排版；过度缩小提示、无法放置即失败，不静默丢失 |
| PDF 转 Markdown | markdown | 本地提取标题、段落、表格、链接和图片，可启用 OCR；不需要 LLM |
| 工作流程 | workflow | 可排序工具链、模板保存/导入/导出、任务隔离；密码不存入模板 |

## 本地产品与在线产品的差异

不复制官网会员、付费、账号体系、Google Drive/Dropbox 登录、在线邀请多人签署、签名证书颁发或跨设备云同步。这些需要独立的在线服务和信任基础设施，不能作为完全离线软件中的等价能力宣称。HiPDF 通过原生文件选择器访问已经同步到 Mac 的文件。

表单自动检测是矩形边框启发式，不包含商业服务的完整表单语义模型。Office 重建、OCR、复杂图文翻译需要校对。翻译不是通用版式引擎，垂直排版、特殊字体及复杂跨栏页面可能需要重新排版模式。PDF/A 当前实现导出并检查标记，尚未宣称所有输出通过完整 ISO 一致性验证。

## 隐私与运行行为

- PDF/Office/OCR/Markdown 操作在本机进程中执行，无分析埋点或自有云服务。
- AI 只在用户启动相应操作后发送文档文字，API Key 放入授权头；Base URL、模型及高级参数由用户设置。
- API Key 存入 macOS 钥匙串，仅通过 stdin 传到短期子进程，不写进命令行、流程模板、日志或历史。
- AI 拒绝携带凭据的 URL、非本机 HTTP 服务及自动重定向；不回显可能含敏感数据的服务端错误正文。
- 每次处理写入私有临时目录，成功后整体提交，失败/取消时清理。保留原件。
- 工作流程为 PDF 输入/输出链，输出图片、Office 文件及 AI 文本的工具暂不进入链。

## 验证入口

`tests/test_engine.py` 包含页序、输入文件哈希、压缩、密码往返、密文清理、表单逻辑值/外观、OCR、Office 包内容、证书签名完整性、工作流程和本地模拟 AI 的集成检查。原生界面及 HTML 分页需要 macOS 运行验证；实体扫描仪和用户自定义 AI 服务需要对应设备或凭据。
