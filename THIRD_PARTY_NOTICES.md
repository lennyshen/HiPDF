# HiPDF 开源组件说明

HiPDF 为独立实现，与 iLovePDF 无隶属或授权关系；不包含其源码、商标图形或服务端接口。

HiPDF 应用源码采用 GNU Affero General Public License v3.0（AGPL-3.0），见 `LICENSE`。本地运行无需购买服务；如需闭源商业分发，须先处理所用组件的相应授权。此处说明实际依赖许可，不代表取得了第三方商业授权。

| 组件 | 用途 | 许可证 / 来源 |
|---|---|---|
| PyMuPDF 1.26.7 / MuPDF | PDF 操作、渲染和文字提取 | AGPL-3.0 / Artifex 商业双重许可；https://pymupdf.readthedocs.io/en/latest/about.html |
| pdf2docx 0.5.8 | 可编辑 DOCX 重建 | AGPL-3.0；https://github.com/ArtifexSoftware/pdf2docx |
| LibreOffice 26.8.0 | Office 导入与 PDF/A 导出 | MPL-2.0 / LGPL-3.0+；https://www.libreoffice.org/about-us/licenses/ |
| Python 3.12 | 隔离处理运行时 | PSF License；https://www.python.org/psf/license/ |
| pypdf | PDF 结构与测试验证 | BSD-3-Clause；https://github.com/py-pdf/pypdf |
| python-docx / python-pptx | Office 文档导出 | MIT；https://github.com/python-openxml |
| openpyxl | Excel 导出 | MIT；https://openpyxl.readthedocs.io/ |
| Pillow | 图像处理 | HPND；https://python-pillow.github.io/ |
| pyHanko | 本地证书数字签名 | MIT；https://github.com/MatthiasValvekens/pyHanko |
| requests | OpenAI 兼容 HTTP 接口 | Apache-2.0；https://requests.readthedocs.io/ |
| pdfplumber | PDF 文本/表格生态依赖 | MIT；https://github.com/jsvine/pdfplumber |

依赖的完整版本写于 `engine/requirements.lock.txt`，安装包中各组件的 `.dist-info` 或 LibreOffice Resources 目录保留原许可与版权文件。NumPy、OpenCV、cryptography、lxml、fonttools 等传递依赖的许可见对应安装目录。

macOS 系统框架 PDFKit、Vision、AppKit、SwiftUI、ImageKit 与 WebKit 由操作系统提供，不单独重新分发。LibreOffice 安装包取自清华镜像，SHA-256 与 Homebrew 记录的官方包一致：`8858d8058da4f862f47559486814e65efc27294da67c5e4bb56b006b1ee59f89`。
