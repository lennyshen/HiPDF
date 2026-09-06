import http.server
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'engine'))
from common import UserError
from ai import chat
import pymupdf as fitz

class ProtocolTests(unittest.TestCase):
    def test_errors_are_explicit_and_secrets_are_not_echoed(self):
        class Handler(http.server.BaseHTTPRequestHandler):
            response_code=401
            def log_message(self,*args):pass
            def do_POST(self):
                self.rfile.read(int(self.headers['Content-Length']))
                self.send_response(self.response_code);self.end_headers()
                if self.response_code==200:self.wfile.write(json.dumps({'choices':[{'message':{'content':'partial'},'finish_reason':'length'}]}).encode())
                else:self.wfile.write(b'{"error":"do-not-echo-this-secret"}')
        server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
        threading.Thread(target=server.serve_forever,daemon=True).start()
        config={'baseURL':f'http://127.0.0.1:{server.server_port}/v1','model':'mock','apiKey':'do-not-echo-this-secret'}
        try:
            with self.assertRaises(UserError) as caught:chat(config,'test','test')
            self.assertIn('401',str(caught.exception));self.assertNotIn(config['apiKey'],str(caught.exception))
            Handler.response_code=200
            with self.assertRaisesRegex(UserError,'截断'):chat(config,'test','test')
        finally:server.shutdown();server.server_close()

    def test_worker_cancel_removes_staging_output(self):
        started=threading.Event()
        release=threading.Event()
        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self,*args):pass
            def do_POST(self):
                self.rfile.read(int(self.headers['Content-Length']));started.set();release.wait(8)
                try:self.send_response(200);self.end_headers();self.wfile.write(b'{"choices":[{"message":{"content":"ok"}}]}')
                except (BrokenPipeError,ConnectionResetError):pass
        server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
        threading.Thread(target=server.serve_forever,daemon=True).start()
        try:
            with tempfile.TemporaryDirectory(prefix='hipdf-cancel-') as directory:
                source=Path(directory)/'input.pdf';doc=fitz.open();doc.new_page().insert_text((40,50),'Synthetic cancellation test');doc.save(source);doc.close()
                request={'action':'summarize','files':[str(source)],'outputDir':str(Path(directory)/'outputs'),'ai':{'baseURL':f'http://127.0.0.1:{server.server_port}/v1','model':'mock'}}
                process=subprocess.Popen([sys.executable,str(ROOT/'engine/worker.py')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
                process.stdin.write(json.dumps(request).encode());process.stdin.close();process.stdin=None
                self.assertTrue(started.wait(10));process.terminate();stdout,stderr=process.communicate(timeout=10)
                self.assertIn('取消',stdout.decode());self.assertFalse(list((Path(directory)/'outputs').iterdir()))
        finally:release.set();server.shutdown();server.server_close()
