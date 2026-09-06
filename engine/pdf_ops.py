from __future__ import annotations
import hashlib
import io
import json
import secrets
from pathlib import Path
import pymupdf as fitz
from PIL import Image, ImageOps, ImageEnhance
from common import *


def merge(files, directory, o):
    if len(files) < 2:
        raise UserError('合并需要至少两个 PDF 文件。')
    out = fitz.open()
    bookmarks = []
    for index, file in enumerate(files):
        progress(f'正在合并 {Path(file).name}', index / len(files))
        with open_pdf(file, o) as doc:
            offset = len(out)
            out.insert_pdf(doc, widgets=True)
            bookmarks.append([1, Path(file).stem, offset + 1])
            bookmarks += [[item[0] + 1, item[1], item[2] + offset] for item in doc.get_toc() if item[2] > 0]
    out.set_toc(bookmarks)
    return [save_pdf(out, output_path(directory, files[0], '合并'))], []


def images_to_pdf(files, directory, o, scan=False):
    out = fitz.open()
    margin = number(o, 'margin', 20, 0, 200)
    for file in files:
        with Image.open(file) as original:
            for frame in range(getattr(original, 'n_frames', 1)):
                original.seek(frame)
                img = ImageOps.exif_transpose(original.copy()).convert('RGB')
                if scan:
                    mode = o.get('scanMode', 'color')
                    if mode in ('gray', 'bw'):
                        img = ImageOps.autocontrast(ImageOps.grayscale(img))
                        if mode == 'bw':
                            img = img.point(lambda x: 255 if x > 160 else 0).convert('RGB')
                size = (595, 842) if o.get('paper', 'a4') == 'a4' else (img.width * .75 + margin * 2, img.height * .75 + margin * 2)
                if o.get('orientation') == 'landscape':
                    size = (max(size), min(size))
                if min(size) <= margin * 2:
                    raise UserError('页边距超过纸张尺寸。')
                page = out.new_page(width=size[0], height=size[1])
                buf = io.BytesIO()
                img.save(buf, format='JPEG', quality=95)
                page.insert_image(fitz.Rect(margin, margin, size[0]-margin, size[1]-margin), stream=buf.getvalue())
    return [save_pdf(out, output_path(directory, files[0], '扫描' if scan else '图片合成'))], []


def split(doc, file, directory, o):
    mode = o.get('splitMode', 'each')
    selected = pages(o.get('pages'), len(doc))
    if mode == 'ranges':
        raw = str(o.get('pages', '')).replace('，', ',')
        if not raw.strip():
            raise UserError('请填写拆分区间，例如 1-3,4-6。')
        groups = [pages(x, len(doc)) for x in raw.split(',')]
    elif mode == 'size':
        group_size = int(number(o, 'groupSize', 1, 1, 100000))
        groups = [selected[i:i+group_size] for i in range(0, len(selected), group_size)]
    else:
        groups = [[p] for p in selected]
    outputs = []
    for index, group in enumerate(groups):
        out = fitz.open()
        for p in group:
            out.insert_pdf(doc, from_page=p, to_page=p, widgets=True)
        outputs.append(save_pdf(out, output_path(directory, file, f'拆分_{index+1:03}')))
        out.close()
    return outputs


def compress(doc, file, directory, o):
    mode = o.get('compression', 'balanced')
    path = output_path(directory, file, '压缩')
    if mode != 'lossless':
        quality, max_dpi = (45, 110) if mode == 'strong' else (75, 160)
        processed = set()
        for page in doc:
            for item in page.get_images(full=True):
                xref = item[0]
                if xref in processed or item[1] != 0:
                    continue
                processed.add(xref)
                try:
                    extracted = doc.extract_image(xref)
                    image = Image.open(io.BytesIO(extracted['image']))
                    if image.mode not in ('RGB', 'L') or min(image.size) < 64:
                        continue
                    rects = page.get_image_rects(xref)
                    if rects:
                        max_width = max(r.width for r in rects) * max_dpi / 72
                        max_height = max(r.height for r in rects) * max_dpi / 72
                        image.thumbnail((max(1, round(max_width)), max(1, round(max_height))))
                    buf = io.BytesIO()
                    image.save(buf, format='JPEG', quality=quality, optimize=True)
                    if len(buf.getvalue()) < len(extracted['image']):
                        page.replace_image(xref, stream=buf.getvalue())
                except (ValueError, OSError):
                    continue
    save_pdf(doc, path, use_objstms=1, deflate_images=True, deflate_fonts=True)
    original = Path(file).stat().st_size
    result = path.stat().st_size
    if result >= original:
        return [str(path)], ['该文件已较紧凑，本次无法进一步减小体积；请比较结果后选用。']
    return [str(path)], [f'体积减少 {(1-result/original)*100:.1f}%，文字仍可搜索。']


def get_regions(o, doc, mode=None):
    regions = o.get('regions', [])
    if isinstance(regions, str):
        regions = json.loads(regions or '[]')
    if not regions:
        return []
    for region in regions:
        page = int(region.get('page', 0))
        if page < 0 or page >= len(doc):
            raise UserError('选区页码超出文档范围。')
        rect_for(doc[page], region['rect'])
    return regions


def edit_document(doc, o, action):
    selected = pages(o.get('pages'), len(doc))
    regions = get_regions(o, doc)
    text = str(o.get('text', '')).strip()
    color = color_value(o.get('color', '#334155'))
    fontsize = number(o, 'fontSize', 20, 4, 150)
    if not regions and action in ('edit', 'sign'):
        regions = [{'page': p, 'rect': [.12, .73, .65, .87], 'mode': o.get('editMode', 'text')} for p in selected]
    if action == 'crop':
        margin = number(o, 'cropMargin', 20, 0, 500)
        for p in selected:
            page = doc[p]
            matching = [r for r in regions if r['page'] == p]
            if matching:
                rect = rect_for(page, matching[-1]['rect'])
                rect += (page.cropbox.x0, page.cropbox.y0, page.cropbox.x0, page.cropbox.y0)
            elif regions and truth(o.get('applyAll', False)):
                rect = rect_for(page, regions[-1]['rect'])
                rect += (page.cropbox.x0, page.cropbox.y0, page.cropbox.x0, page.cropbox.y0)
            elif regions:
                continue
            else:
                rect = page.cropbox + (margin, margin, -margin, -margin)
            if rect.is_empty:
                raise UserError('裁剪边距过大。')
            page.set_cropbox(rect)
        return []
    if action == 'redact':
        terms = [s.strip() for s in str(o.get('terms', '')).splitlines() if s.strip()]
        if not terms and not regions:
            raise UserError('请框选需要删除的区域，或填写需要删除的文字。')
        count = 0
        for p in selected:
            page = doc[p]
            rects = [rect_for(page, r['rect']) for r in regions if r['page'] == p]
            for term in terms:
                rects += page.search_for(term)
            for rect in rects:
                page.add_redact_annot(rect, fill=(0, 0, 0))
                count += 1
            if rects:
                page.apply_redactions(images=2, graphics=2, text=0)
        if count == 0:
            raise UserError('未找到匹配文字。扫描件请使用框选区域，或先运行 OCR。')
        # Remove hidden channels that could retain redacted content.
        doc.scrub(attached_files=True, clean_pages=True, embedded_files=True, hidden_text=True,
                  javascript=True, metadata=True, redactions=True, remove_links=True,
                  reset_fields=True, reset_responses=True, thumbnails=True, xml_metadata=True)
        doc.set_toc([])
        return [f'已永久删除 {count} 个区域，并清理附件、元数据和隐藏内容。请检查所有敏感信息所在页面。']
    image_path = str(o.get('imagePath', ''))
    if action == 'sign' and not image_path and not text and not any(r.get('points') for r in regions):
        raise UserError('请填写签名文字、导入签名图片，或在页面上手写签名。')
    for region in regions:
        page = doc[int(region['page'])]
        rect = rect_for(page, region['rect'])
        mode = region.get('mode', o.get('editMode', 'text'))
        content = str(region.get('text', text))
        if image_path and (action == 'sign' or mode == 'image'):
            page.insert_image(rect, filename=image_path)
        elif mode == 'ink' and region.get('points'):
            points = [fitz.Point(x*page.cropbox.width, y*page.cropbox.height) for x,y in region['points']]
            if len(points) > 1:
                annot = page.add_ink_annot([points])
                annot.set_colors(stroke=color)
                annot.set_border(width=2)
                annot.update()
        elif mode == 'rectangle':
            page.draw_rect(rect, color=color, width=2)
        elif mode == 'highlight':
            page.draw_rect(rect, color=None, fill=(1, .83, .15), fill_opacity=.3)
        elif mode == 'image':
            raise UserError('请先选择要添加的图片。')
        else:
            if not content:
                raise UserError('请填写要添加的文字。')
            text_in_rect(page, rect, content, fontsize, color)
    return []


def watermark(doc, o, page_numbers=False):
    selected = pages(o.get('pages'), len(doc))
    opacity = number(o, 'opacity', .22, .01, 1)
    size = number(o, 'fontSize', 36 if not page_numbers else 12, 4, 150)
    text = str(o.get('text', '{page} / {total}' if page_numbers else '')).strip()
    image = str(o.get('imagePath', ''))
    if not text and not image:
        raise UserError('请填写水印文字或选择图片。')
    for index, p in enumerate(selected):
        page = doc[p]
        w, h = page.cropbox.width, page.cropbox.height
        pos = o.get('position', 'bottom' if page_numbers else 'center')
        y = {'top': 20, 'center': h*.44, 'bottom': h-50}.get(pos, h*.44)
        rect = fitz.Rect(25, y, w-25, min(h-5, y + (40 if page_numbers else h*.16)))
        if image and not page_numbers:
            with Image.open(image) as source:
                rgba = source.convert('RGBA')
                rgba.putalpha(rgba.getchannel('A').point(lambda v: round(v*opacity)))
                buf = io.BytesIO()
                rgba.save(buf, 'PNG')
                page.insert_image(rect, stream=buf.getvalue())
        else:
            actual = text.replace('{page}', str(index + int(number(o, 'startNumber', 1, 0)))).replace('{total}', str(len(selected)))
            text_in_rect(page, rect, actual, size, color_value(o.get('color')), 1 if page_numbers else opacity, align=1)


def forms(doc, o):
    mode = o.get('formMode', 'fill')
    if mode == 'fill':
        values = o.get('formValues', {})
        if isinstance(values, str):
            values = json.loads(values or '{}')
        if not values:
            raise UserError('没有填写任何表单字段；可切换到创建字段。')
        found = set()
        for page in doc:
            for widget in list(page.widgets() or []):
                if widget.field_name in values:
                    val = values[widget.field_name]
                    if widget.field_type in (fitz.PDF_WIDGET_TYPE_CHECKBOX, fitz.PDF_WIDGET_TYPE_RADIOBUTTON):
                        on = widget.on_state() or 'Yes'
                        widget.field_value = on if truth(val) or str(val) == str(on) else 'Off'
                    else:
                        widget.field_value = str(val)
                    widget.update()
                    found.add(widget.field_name)
        missing = set(values) - found
        if missing:
            raise UserError('未找到字段：' + ', '.join(sorted(missing)))
    else:
        regions = get_regions(o, doc)
        if mode == 'detect':
            regions = []
            for page in doc:
                existing = [w.rect for w in page.widgets() or []]
                for drawing in page.get_drawings():
                    r = drawing['rect']
                    is_box = any(item[0] == 're' for item in drawing['items'])
                    if is_box and 10 <= r.height <= 55 and 10 <= r.width <= page.cropbox.width*.9 and not any(r.intersects(e) for e in existing):
                        regions.append({'page': page.number, 'rect': [r.x0/page.cropbox.width, r.y0/page.cropbox.height, r.x1/page.cropbox.width, r.y1/page.cropbox.height],
                                        'fieldType': 'checkbox' if abs(r.width-r.height) < 5 else 'text'})
            if not regions:
                raise UserError('未检测到清晰的表单边框。请在页面上框选区域创建字段。')
        if not regions:
            raise UserError('请在页面预览上框选新字段区域。')
        names = {w.field_name for p in doc for w in p.widgets() or []}
        for index, region in enumerate(regions):
            page = doc[region['page']]
            widget = fitz.Widget()
            base_name = str(o.get('fieldName', '字段')).strip() or '字段'
            candidate = f'{base_name}_{index+1}' if len(regions) > 1 else base_name
            while candidate in names:
                candidate += '_2'
            names.add(candidate)
            widget.field_name = candidate
            field_type = region.get('fieldType', o.get('fieldType', 'text'))
            widget.field_type = {'text': fitz.PDF_WIDGET_TYPE_TEXT, 'checkbox': fitz.PDF_WIDGET_TYPE_CHECKBOX,
                                 'radio': fitz.PDF_WIDGET_TYPE_RADIOBUTTON, 'list': fitz.PDF_WIDGET_TYPE_LISTBOX,
                                 'combo': fitz.PDF_WIDGET_TYPE_COMBOBOX}.get(field_type, fitz.PDF_WIDGET_TYPE_TEXT)
            widget.rect = rect_for(page, region['rect'])
            widget.border_width = 1
            widget.border_color = (.55, .58, .65)
            widget.text_fontsize = 12
            if field_type in ('list', 'combo'):
                widget.choice_values = [v.strip() for v in str(o.get('choices', '')).splitlines() if v.strip()]
                if not widget.choice_values:
                    raise UserError('请逐行填写列表选项。')
            widget.field_value = 'Off' if field_type in ('checkbox', 'radio') else str(o.get('fieldValue', ''))
            page.add_widget(widget)
    if truth(o.get('flatten', False)):
        doc.bake(annots=False, widgets=True)


def sign_certificate(file, directory, o):
    from pyhanko.sign import signers, fields
    from pyhanko.pdf_utils.incremental_writer import IncrementalPdfFileWriter
    cert = str(o.get('certificate', ''))
    if not Path(cert).is_file():
        raise UserError('请选择 PKCS#12 证书文件（.p12 或 .pfx）。')
    signer = signers.SimpleSigner.load_pkcs12(cert, passphrase=str(o.get('certPassword', '')).encode())
    if signer is None:
        raise UserError('无法读取签名证书，请检查证书密码。')
    path = output_path(directory, file, '数字签名')
    with open(file, 'rb') as source, open(path, 'wb') as target:
        writer = IncrementalPdfFileWriter(source)
        if writer.prev.encrypted:
            writer.encrypt(str(o.get('password', '')))
        metadata = signers.PdfSignatureMetadata(field_name='HiPDF_' + secrets.token_hex(4), reason=str(o.get('reason', 'Document approval')))
        signers.sign_pdf(writer, signature_meta=metadata, signer=signer, output=target)
    return [str(path)], ['已使用本地证书签名；未连接时间戳服务。证书信任取决于接收方的信任库。']


def operate(action, files, directory, o):
    if action == 'merge':
        return merge(files, directory, o)
    if action in ('imageToPDF', 'scan'):
        return images_to_pdf(files, directory, o, scan=action == 'scan')
    outputs, notes = [], []
    for idx, file in enumerate(files):
        progress(f'处理 {idx+1}/{len(files)}：{Path(file).name}', idx/len(files))
        if action == 'sign' and o.get('signMode') == 'certificate':
            paths, messages = sign_certificate(file, directory, o)
            outputs += paths
            notes += messages
            continue
        with open_pdf(file, o) as doc:
            path = output_path(directory, file, action)
            selected = pages(o.get('pages'), len(doc), allow_duplicates=action == 'organize')
            if action == 'split':
                outputs += split(doc, file, directory, o)
                continue
            elif action in ('delete', 'extract', 'organize'):
                if action == 'delete':
                    if not str(o.get('pages', '')).strip():
                        raise UserError('请明确填写要删除的页码。')
                    selected = [p for p in range(len(doc)) if p not in selected]
                    if not selected:
                        raise UserError('不能删除所有页面。')
                doc.select(selected)
            elif action == 'compress':
                paths, messages = compress(doc, file, directory, o)
                outputs += paths
                notes += messages
                continue
            elif action == 'rotate':
                rotation = int(number(o, 'rotation', 90))
                if rotation not in (-90, 90, 180, 270):
                    raise UserError('旋转角度必须为 90、180 或 270 度。')
                for p in selected:
                    doc[p].set_rotation((doc[p].rotation + rotation) % 360)
            elif action == 'encrypt':
                password = str(o.get('newPassword', ''))
                if not password:
                    raise UserError('请填写新的打开密码。')
                if len(password) > 40:
                    raise UserError('此加密引擎支持最多 40 个字符的打开密码。')
                permissions = 0
                if truth(o.get('allowPrint', True)):
                    permissions |= fitz.PDF_PERM_PRINT | fitz.PDF_PERM_PRINT_HQ
                if truth(o.get('allowCopy', False)):
                    permissions |= fitz.PDF_PERM_COPY
                outputs.append(save_pdf(doc, path, encryption=fitz.PDF_ENCRYPT_AES_256,
                                        owner_pw=secrets.token_urlsafe(24), user_pw=password, permissions=permissions))
                continue
            elif action == 'unlock':
                pass  # authenticated in open_pdf; output encryption explicitly disabled
            elif action == 'repair':
                notes.append('已重建可读取的 PDF 对象和交叉引用；无法恢复源文件中已缺失的数据。')
            elif action in ('watermark', 'numbers'):
                watermark(doc, o, action == 'numbers')
            elif action in ('edit', 'crop', 'redact', 'sign'):
                notes += edit_document(doc, o, action)
            elif action == 'forms':
                forms(doc, o)
            else:
                raise UserError(f'未知 PDF 操作：{action}')
            outputs.append(save_pdf(doc, path, clean=action in ('repair', 'redact')))
    return outputs, notes
