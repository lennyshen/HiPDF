"""Shared local-only primitives. Never invoke a shell with document data."""
from __future__ import annotations
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
import pymupdf as fitz


class UserError(Exception):
    pass


def emit(event: dict):
    print(json.dumps(event, ensure_ascii=False), file=sys.__stdout__, flush=True)


def progress(message: str, value: float = 0):
    emit({"type": "progress", "message": message, "progress": value})


def truth(value):
    return value is True or str(value).lower() in ("true", "1", "yes")


def number(options, key, default, minimum=None, maximum=None):
    try:
        value = float(options.get(key, default))
    except (ValueError, TypeError):
        raise UserError(f"参数 {key} 需要填写数字。")
    if not __import__('math').isfinite(value):
        raise UserError(f"参数 {key} 必须是有限数字。")
    if minimum is not None and value < minimum or maximum is not None and value > maximum:
        raise UserError(f"参数 {key} 超出允许范围。")
    return value


def pages(spec, count, allow_duplicates=False):
    """One-based inclusive ranges; ordering is significant, invalid pages never disappear."""
    if not str(spec or '').strip() or str(spec).strip().lower() in ('all', '全部'):
        return list(range(count))
    normalized = str(spec).replace('，', ',').replace('；', ',').replace(';', ',').replace('–', '-').replace(' ', '')
    result = []
    for part in normalized.split(','):
        if not re.fullmatch(r'\d+(?:-\d+)?', part):
            raise UserError("页码格式应为 1-3,5,8；也可留空选择全部页面。")
        bounds = [int(x) for x in part.split('-')]
        start, end = bounds[0], bounds[-1]
        if min(bounds) < 1 or max(bounds) > count:
            raise UserError(f"页码 {part} 超出范围，此文件共 {count} 页。")
        for p in range(start, end + (1 if end >= start else -1), 1 if end >= start else -1):
            if allow_duplicates or p - 1 not in result:
                result.append(p - 1)
    if not result:
        raise UserError("请选择至少一页。")
    return result


def open_pdf(path, options=None):
    try:
        doc = fitz.open(str(path))
    except Exception as exc:
        raise UserError(f"无法打开 {Path(path).name}：{str(exc)[:160]}") from exc
    if not doc.is_pdf:
        doc.close()
        raise UserError(f"{Path(path).name} 不是 PDF 文件。")
    if doc.needs_pass and not doc.authenticate(str((options or {}).get('password', ''))):
        doc.close()
        raise UserError(f"{Path(path).name} 需要正确的打开密码。")
    if len(doc) == 0:
        doc.close()
        raise UserError("PDF 中没有可处理的页面。")
    return doc


def output_path(directory, source, suffix, extension='pdf'):
    stem = re.sub(r'[/:\x00-\x1f]', '_', Path(source).stem)[:100] or 'document'
    path = Path(directory) / f'{stem}_{suffix}.{extension}'
    index = 2
    while path.exists():
        path = Path(directory) / f'{stem}_{suffix}_{index}.{extension}'
        index += 1
    return path


def save_pdf(doc, path, **kwargs):
    options = {'garbage': 4, 'deflate': True, 'encryption': fitz.PDF_ENCRYPT_NONE}
    options.update(kwargs)
    doc.save(str(path), **options)
    with fitz.open(str(path)) as check:
        if len(check) < 1:
            raise UserError('输出 PDF 验证失败。')
    return str(path)


def rect_for(page, values):
    """Coordinates are normalized within the unrotated crop box, top-left origin."""
    if not isinstance(values, (list, tuple)) or len(values) != 4:
        raise UserError('请选择页面区域。')
    values = [float(v) for v in values]
    if not all(0 <= v <= 1 for v in values):
        raise UserError('区域必须位于页面内。')
    rect = fitz.Rect(values[0] * page.cropbox.width, values[1] * page.cropbox.height,
                     values[2] * page.cropbox.width, values[3] * page.cropbox.height)
    if rect.is_empty:
        raise UserError('区域宽度和高度必须大于零。')
    return rect


def text_in_rect(page, rect, text, size=16, color=(0.12, 0.16, 0.22), opacity=1, align=0, invisible=False):
    font = 'china-s' if any(ord(c) > 255 for c in text) else 'helv'
    # Textbox returns a negative value on overflow; never silently drop a label.
    for actual_size in (size, size * .85, size * .7, size * .55, size * .4):
        shape = page.new_shape()
        left = shape.insert_textbox(rect, text, fontsize=actual_size, fontname=font,
                                   color=color, align=align, fill_opacity=opacity,
                                   render_mode=3 if invisible else 0)
        if left >= 0:
            shape.commit()
            return actual_size
    raise UserError('文字无法放入所选区域，请扩大区域或缩短文字。')


def color_value(value, default='#334155'):
    value = str(value or default).lstrip('#')
    if not re.fullmatch('[0-9a-fA-F]{6}', value):
        raise UserError('颜色应为六位十六进制值。')
    return tuple(int(value[i:i+2], 16) / 255 for i in (0, 2, 4))


def run_program(args, timeout=180):
    try:
        result = subprocess.run([str(a) for a in args], capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        raise UserError('处理超时，请减少文件数量后重试。') from exc
    if result.returncode:
        raise UserError('本地转换引擎处理失败：' + result.stderr.decode(errors='replace')[-400:])
    return result.stdout


def libreoffice():
    root = Path(__file__).resolve().parent.parent
    candidates = [os.environ.get('HIPDF_LIBREOFFICE', ''),
                  str(root / 'LibreOffice.app/Contents/MacOS/soffice'),
                  str(root / '.runtime/LibreOffice.app/Contents/MacOS/soffice'),
                  '/Applications/LibreOffice.app/Contents/MacOS/soffice']
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return candidate
    raise UserError('未找到 Office 转换引擎。请安装 LibreOffice 或重新构建包含引擎的 HiPDF。')


def office_convert(source, directory, format_spec, infilter=None):
    with tempfile.TemporaryDirectory(prefix='hipdf-office-') as profile:
        args = [libreoffice(), '-env:UserInstallation=' + Path(profile).as_uri(),
                '--headless', '--nologo', '--nodefault', '--norestore', '--nolockcheck']
        if infilter:
            args += ['--infilter=' + infilter]
        args += ['--convert-to', format_spec, '--outdir', str(directory), str(source)]
        run_program(args, timeout=240)
    result = Path(directory) / (Path(source).stem + '.' + format_spec.split(':')[0])
    if not result.exists() or result.stat().st_size == 0:
        raise UserError('Office 引擎没有生成有效输出。文件可能不受支持或已加密。')
    return result
