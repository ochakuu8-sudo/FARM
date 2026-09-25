"""ブラウザ版の重さの計測。書き出した build/web を Chrome（画面なし）で開き、ゲームの計測（--debug=bench）の結果を集める。
CPU を遅くする倍率（Chrome の開発者ツールと同じ仕組み）を変えて、スマホ相当の速さでも測る。
  1倍 … このPC   4倍 … 中くらいのスマホの目安   6倍 … 古い・安いスマホの目安

    python game_v2/tools/web_bench.py [--rates=1,4,6] [--mobile] [--profile]

--mobile はスマホの画面（横 915×412、端末の画素比 2.6、タッチ）にする。ゲームは Perf.lite（軽量）で動く。
先に build/web へ書き出しておくこと（game_v2/tools/web_export.py）。bench.html は書き出しのときに作られる。
"""
import asyncio
import functools
import http.server
import json
import os
import shutil
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request

import aiohttp

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
WEB = os.path.join(ROOT, "build", "web")
CHROME = [r"C:\Program Files\Google\Chrome\Application\chrome.exe",
          r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"]
PORT = 8071
DEBUG_PORT = 9333
VERBOSE = "--verbose" in sys.argv
PROFILE = "--profile" in sys.argv
GLLOG = "--gl-log" in sys.argv
GL_HOOK = r"""
(() => {
  const P = WebGL2RenderingContext.prototype;
  const shaders = new WeakMap(), progs = new WeakMap();
  const ss = P.shaderSource; P.shaderSource = function (sh, src) { shaders.set(sh, src); return ss.call(this, sh, src); };
  const at = P.attachShader; P.attachShader = function (pr, sh) { const l = progs.get(pr) || []; l.push(shaders.get(sh) || ''); progs.set(pr, l); return at.call(this, pr, sh); };
  const gp = P.getProgramParameter; P.getProgramParameter = function (pr, pn) {
    const t = performance.now(); const r = gp.call(this, pr, pn); const d = performance.now() - t;
    window.__glp = (window.__glp||0) + d; window.__gln = (window.__gln||0) + 1;
    if (d > 3) { const src = (progs.get(pr) || []).join(' ');
      const defs = (src.match(/#define [A-Z_0-9]+/g) || []).slice(0, 60).filter(x=>!/MAX_VIEWS|#define V$/.test(x)).join(' ');
      const hint = /actor_row/.test(src) ? 'cutout' : (/backdrop|ember/.test(src) ? 'backdrop' : 'other');
      console.log('GLPROG ' + d.toFixed(0) + 'ms len=' + src.length + ' ' + hint + ' ' + defs); }
    return r; };
})();
"""


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def serve():
    handler = functools.partial(Quiet, directory=WEB)
    socketserver.TCPServer.allow_reuse_address = True
    httpd = socketserver.ThreadingTCPServer(("127.0.0.1", PORT), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


async def run_once(rate: float, mobile: bool, timeout: float = 420.0) -> list:
    exe = next((c for c in CHROME if os.path.exists(c)), None)
    profile = tempfile.mkdtemp(prefix="web_bench_")
    proc = subprocess.Popen([exe, "--headless=new", "--remote-debugging-port=%d" % DEBUG_PORT,
                             "--user-data-dir=" + profile, "--no-first-run", "--no-default-browser-check",
                             "--enable-gpu", "--ignore-gpu-blocklist", "--enable-unsafe-swiftshader",
                             "--autoplay-policy=no-user-gesture-required", "about:blank"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    lines = []
    try:
        ws_url = None
        for _ in range(100):
            try:
                with urllib.request.urlopen("http://127.0.0.1:%d/json/list" % DEBUG_PORT) as r:
                    pages = [t for t in json.load(r) if t.get("type") == "page"]
                if pages:
                    ws_url = pages[0]["webSocketDebuggerUrl"]
                    break
            except OSError:
                pass
            await asyncio.sleep(0.1)
        async with aiohttp.ClientSession() as session:
            async with session.ws_connect(ws_url, max_msg_size=0) as ws:
                n = 0

                async def send(method, params=None):
                    nonlocal n
                    n += 1
                    await ws.send_json({"id": n, "method": method, "params": params or {}})

                await send("Runtime.enable")
                await send("Emulation.setCPUThrottlingRate", {"rate": rate})
                if mobile:
                    await send("Emulation.setDeviceMetricsOverride",
                               {"width": 915, "height": 412, "deviceScaleFactor": 2.6, "mobile": True})
                    await send("Emulation.setTouchEmulationEnabled", {"enabled": True, "maxTouchPoints": 5})
                    await send("Emulation.setUserAgentOverride", {"userAgent": "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36", "platform": "Android"})
                else:
                    await send("Emulation.setDeviceMetricsOverride",
                               {"width": 1600, "height": 900, "deviceScaleFactor": 1, "mobile": False})
                if GLLOG:
                    # シェーダーのコンパイル（リンクの完了待ち）を1つずつ記録する
                    await send("Page.enable")
                    await send("Page.addScriptToEvaluateOnNewDocument", {"source": GL_HOOK})
                if PROFILE:
                    await send("Profiler.enable")
                    await send("Profiler.setSamplingInterval", {"interval": 500})
                t0 = time.time()
                await send("Page.navigate", {"url": "http://127.0.0.1:%d/bench.html" % PORT})
                profiling = False
                while time.time() - t0 < timeout:
                    try:
                        msg = await ws.receive(timeout=5)
                    except asyncio.TimeoutError:
                        continue
                    if msg.type != aiohttp.WSMsgType.TEXT:
                        break
                    data = json.loads(msg.data)
                    if data.get("method") == "Runtime.consoleAPICalled":
                        text = " ".join(str(a.get("value", a.get("description", ""))) for a in data["params"]["args"])
                        if VERBOSE or text.startswith("BENCH") or text.startswith("GLPROG") or "ERROR" in text or "SCRIPT" in text or "OpenGL" in text:
                            lines.append(text)
                        # --profile：牧場に入る直前から入り終わるまでの CPU の内訳（関数ごとの自分の時間）
                        if GLLOG and text.startswith("BENCH startup_ms"):
                            await send("Runtime.evaluate", {"expression": GL_HOOK})
                        if PROFILE and text.startswith("BENCH warm_up_ms") and not profiling:
                            profiling = True
                            await send("Profiler.start")
                        if GLLOG and text.startswith("BENCH enter_ranch"):
                            await ws.send_json({"id": 99998, "method": "Runtime.evaluate", "params": {"expression": "JSON.stringify({n:window.__gln,ms:window.__glp,proto:typeof WebGL2RenderingContext.prototype.getProgramParameter, hooked: String(WebGL2RenderingContext.prototype.getProgramParameter).slice(0,40)})", "returnByValue": True}})
                        if PROFILE and profiling and text.startswith("BENCH enter_ranch"):
                            profiling = False
                            n += 1
                            await ws.send_json({"id": 99999, "method": "Profiler.stop"})
                        if text.startswith("BENCH done"):
                            break
                    if data.get("id") == 99998:
                        lines.append("GLHOOK " + str(data.get("result", {}).get("result", {}).get("value")))
                    if data.get("id") == 99999:
                        lines.extend(summarize(data["result"]["profile"]))
                lines.append("BENCH wall_s=%.1f" % (time.time() - t0))
    finally:
        proc.terminate()
        try:
            proc.wait(5)
        except subprocess.TimeoutExpired:
            proc.kill()
        shutil.rmtree(profile, ignore_errors=True)
    return lines


def summarize(profile: dict, top: int = 25) -> list:
    nodes = {n["id"]: n for n in profile["nodes"]}
    self_time = {}
    deltas = profile.get("timeDeltas", [])
    for sid, dt in zip(profile.get("samples", []), deltas):
        cf = nodes[sid]["callFrame"]
        key = "%s  %s" % (cf.get("functionName") or "(anonymous)", cf.get("url", "").rsplit("/", 1)[-1])
        self_time[key] = self_time.get(key, 0) + dt
    total = sum(self_time.values()) or 1
    out = ["PROFILE total %.0fms" % (total / 1000.0)]
    for k, v in sorted(self_time.items(), key=lambda x: -x[1])[:top]:
        out.append("PROFILE %6.0fms %4.1f%%  %s" % (v / 1000.0, v * 100.0 / total, k))
    return out


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    rates = [1.0, 4.0, 6.0]
    mobile = False
    for a in sys.argv[1:]:
        if a.startswith("--rates="):
            rates = [float(x) for x in a.split("=", 1)[1].split(",")]
        if a == "--mobile":
            mobile = True
    if not os.path.exists(os.path.join(WEB, "bench.html")):
        print("build/web/bench.html がない。先に書き出す（game_v2/tools/web_export.py）")
        return 1
    httpd = serve()
    try:
        for rate in rates:
            print("== CPU %.0f倍%s" % (rate, "（スマホの画面）" if mobile else ""))
            for line in asyncio.run(run_once(rate, mobile)):
                print("  " + line)
    finally:
        httpd.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
