#!/usr/bin/env python3
"""One job per process. JSON stdin, NDJSON stdout. Transactional output directories."""
from __future__ import annotations
import contextlib
import datetime
import json
import os
import shutil
import signal
import sys
import tempfile
import uuid
from pathlib import Path
from common import *

PDF_ACTIONS={'merge','split','compress','delete','extract','organize','imageToPDF','scan','rotate','numbers','watermark','crop','edit','forms','unlock','encrypt','sign','redact','repair'}
CONVERT_ACTIONS={'wordToPDF','pptToPDF','excelToPDF','pdfToWord','pdfToPPT','pdfToExcel','pdfToImage','pdfa','ocr','markdown','compare'}
WORKFLOW_ACTIONS={'merge','split','compress','delete','extract','organize','rotate','numbers','watermark','crop','unlock','repair','ocr','pdfa'}


def inspect(files,options):
    records=[]
    for file in files:
        record={'path':str(file),'name':Path(file).name,'bytes':Path(file).stat().st_size,'pages':0,'locked':False,'fields':[]}
        if str(file).lower().endswith('.pdf'):
            import pymupdf as fitz
            with fitz.open(file) as doc:
                record['locked']=bool(doc.needs_pass and not doc.authenticate(str(options.get('password',''))))
                record['pages']=len(doc)
                if not record['locked']:
                    for page in doc:
                        for widget in page.widgets() or []:
                            record['fields'].append({'name':widget.field_name,'value':str(widget.field_value or ''),
                                'type':widget.field_type_string,'choices':widget.choice_values or [],'page':page.number})
        records.append(record)
    return records


def dispatch(action,files,directory,options,config):
    if action in PDF_ACTIONS:
        from pdf_ops import operate
        return operate(action,files,directory,options)
    if action in CONVERT_ACTIONS:
        from converters import operate
        return operate(action,files,directory,options)
    if action in ('summarize','translate'):
        from ai import operate
        return operate(action,files,directory,options,config)
    if action=='workflow':
        steps=options.get('steps',[])
        if not steps:
            raise UserError('请添加至少一个工作流程步骤。')
        current=files
        notes=[]
        for index,step in enumerate(steps):
            if step.get('tool') not in WORKFLOW_ACTIONS:
                raise UserError('流程包含不支持的工具：'+str(step.get('tool')))
            folder=Path(directory)/f'{index+1:02}_{step["tool"]}'
            folder.mkdir()
            progress(f'流程步骤 {index+1}/{len(steps)}',index/len(steps))
            step_options=step.get('options',{})
            if 'password' not in step_options and options.get('password'):
                step_options=dict(step_options,password=options['password'])
            current,messages=dispatch(step['tool'],current,folder,step_options,config)
            notes+=messages
        return current,notes
    raise UserError('尚不支持的操作：'+str(action))


def execute(request):
    action=request.get('action','')
    files=[str(Path(f).expanduser().resolve()) for f in request.get('files',[])]
    options=request.get('options',{})
    config=request.get('ai',{})
    if action=='health':
        try:
            lo=libreoffice()
        except UserError:
            lo=''
        try:
            from converters import ocr_helper
            ocr=ocr_helper()
        except UserError:
            ocr=''
        return {'ok':True,'engine':'PyMuPDF '+fitz.VersionBind,'office':bool(lo),'ocr':bool(ocr)}
    if action=='aiTest':
        from ai import chat
        reply=chat(config,'You are a connectivity tester.','Reply with exactly: HiPDF connection OK')
        return {'ok':True,'message':reply}
    if not files:
        raise UserError('请添加需要处理的文件。')
    for file in files:
        if not Path(file).is_file():
            raise UserError('文件已移动或不存在：'+Path(file).name)
    if action=='inspect':
        return {'ok':True,'files':inspect(files,options)}
    root=Path(request.get('outputDir') or Path.home()/'Documents/HiPDF').expanduser().resolve()
    root.mkdir(parents=True,exist_ok=True)
    job=f'HiPDF-{action}-{datetime.datetime.now():%Y%m%d-%H%M%S}-{uuid.uuid4().hex[:6]}'
    stage=Path(tempfile.mkdtemp(prefix='.hipdf-working-',dir=root))
    os.chmod(stage,0o700)
    try:
        outputs,notes=dispatch(action,files,stage,options,config)
        if not outputs or any(not Path(f).is_file() or Path(f).stat().st_size==0 for f in outputs):
            raise UserError('没有生成有效输出。')
        destination=root/job
        relative=[Path(f).relative_to(stage) for f in outputs]
        stage.rename(destination)
        return {'ok':True,'outputs':[str(destination/p) for p in relative],'notes':list(dict.fromkeys(notes)),
                'directory':str(destination)}
    finally:
        if stage.exists():
            shutil.rmtree(stage)


def main():
    # Convert SIGTERM to structured cleanup. The parent also terminates nested converters.
    def cancelled(*_):
        raise UserError('任务已取消。')
    signal.signal(signal.SIGTERM,cancelled)
    protocol=sys.stdout
    try:
        request=json.load(sys.stdin)
        # Third-party libraries may print diagnostics. Keep protocol clean.
        with contextlib.redirect_stdout(sys.stderr):
            result=execute(request)
        print(json.dumps(dict(type='result',**result),ensure_ascii=False),file=protocol,flush=True)
    except UserError as exc:
        print(json.dumps({'type':'result','ok':False,'error':str(exc)},ensure_ascii=False),file=protocol,flush=True)
        return 1
    except Exception as exc:
        # Only the exception class is exposed; third-party errors can contain input secrets.
        print(json.dumps({'type':'result','ok':False,'error':f'处理失败（{type(exc).__name__}）。请检查文件与参数。'},ensure_ascii=False),file=protocol,flush=True)
        return 1
    return 0


if __name__=='__main__':
    sys.exit(main())
