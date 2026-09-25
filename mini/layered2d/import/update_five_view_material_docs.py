from pathlib import Path
import html, zipfile
ROOT=Path(__file__).resolve().parents[3]
DOC=ROOT/'docs/素材制作テンプレート'
p=DOC/'README.md';s=p.read_text(encoding='utf-8')
s=s.replace('**更新：新規素材は斜め後ろを含む5方向に対応しました。** [番号・登録方法](5方向素材の登録.md)を先に確認してください。旧4方向素材も使用可能です。下記の20枚は旧構成で、5方向一式は25枚です。','**全キャラを5方向素材へ統一しました。** 冒険者・ゴブリン・下地キャラを含め、各モジュールに斜め後ろまで必要です。[番号・登録方法](5方向素材の登録.md)。4方向のみの新規登録は受け付けません。')
s=s.replace('4方向','5方向').replace('20枚','25枚').replace('40枚','75枚').replace('上着＋袖の8枚','上着＋袖の10枚').replace('… single-4.png','… single-5.png')
s=s.replace('5方向のみの新規登録は受け付けません。','4方向のみの新規登録は受け付けません。')
s=s.replace('| `single-4.png` | 背面 | 後頭部・背中・臀部・踵。背面に顔を描かない |','| `single-4.png` | 背面 | 後頭部・背中・臀部・踵。背面に顔を描かない |\n| `single-5.png` | 斜め後ろ | 画面左向きで背中と側面が見える135度。目・口を描かない |')
s=s.replace('正面・斜め・横を並べ','正面・斜め前・横・斜め後ろ・背面を並べ')
p.write_text(s,encoding='utf-8')
p=DOC/'依頼票_コピー用.md';s=p.read_text(encoding='utf-8').replace('4=背面。','4=背面、5=斜め後ろ（背中と左側面が見える135度）。').replace('`single-4.png`','`single-5.png`').replace('背面は後頭部です。','背面と斜め後ろは後頭部です。斜め後ろには耳と横の輪郭が見え、目・口は描きません。').replace('正面・斜め・横、背面の描き忘れ','正面・斜め前・横・斜め後ろ・背面の描き忘れ');p.write_text(s,encoding='utf-8')
p=ROOT/'mini/layered2d/README.md';s=p.read_text(encoding='utf-8');lines=s.splitlines();lines[2]='**[全キャラ共通の5方向素材規約](../../docs/素材制作テンプレート/5方向素材の登録.md)**。冒険者・ゴブリン・下地の全3体を移行済み。各モジュールに5方向が必須です。`5方向素材プレビューを起動.cmd` で確認できます。';s='\n'.join(lines)+'\n';s=s.replace('4方向','5方向').replace('20枚','25枚').replace('"0"〜"3"','"0"〜"4"');p.write_text(s,encoding='utf-8')

KIT=DOC/'anima_i2i'
views=[('01_front','正面'),('02_quarter','斜め前'),('03_side','横'),('05_rear_quarter','斜め後ろ'),('04_back','背面')]
modules=[('01_head','頭'),('02_upper_body','上半身'),('03_lower_body','腰・骨盤'),('04_arm','片腕'),('05_leg','片脚')]
cards=[];links=[]
for kind,title in [('adventurer','冒険者'),('goblin','ゴブリン'),('neutral_base','無地の下地')]:
    for module,label in modules:
        for view,direction in views:
            name=f'{module}_{view}'
            image=f'{kind}/input/{name}.png' if kind=='neutral_base' else f'{kind}/{name}.png'
            text=f'{kind}/prompts/{name}.txt' if kind=='neutral_base' else f'{kind}/{name}.txt'
            prompt=(KIT/text).read_text(encoding='utf-8')
            cards.append(f'<article data-kind="{kind}"><h3>{title} · {label} · {direction}</h3><a href="{image}"><img loading="lazy" src="{image}" alt="{title} {label} {direction}"></a><p><a download href="{image}">入力PNG</a> / <a href="{text}">文章</a></p><textarea>{html.escape(prompt)}</textarea><button onclick="copyPrompt(this)">プロンプトをコピー</button></article>')
            links.append(f'| {title} | {label} | {direction} | [PNG]({image}) | [文章]({text}) |')
page='''<!doctype html><html lang="ja"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>全キャラ共通・5方向素材</title><style>body{margin:0;background:#15222b;color:#edf3f8;font-family:Meiryo,sans-serif}main{max-width:1500px;margin:auto;padding:24px}h1{font-size:26px}p{line-height:1.8}a{color:#93e8d4}nav{position:sticky;top:0;padding:12px;background:#15222bf5;display:flex;gap:24px;align-items:center}.grid{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:14px}article{background:#253944;padding:12px;border-radius:10px}article[hidden]{display:none}h3{font-size:14px}img{display:block;width:100%;aspect-ratio:1;object-fit:contain;background:#e5e7eb}textarea{box-sizing:border-box;width:100%;height:180px;background:#12242e;color:white;line-height:1.6}button,select{padding:10px;background:#3e655e;color:white;border:0;border-radius:5px}@media(max-width:1000px){.grid{grid-template-columns:repeat(2,1fr)}}@media(max-width:500px){.grid{grid-template-columns:1fr}}</style><main><h1>全キャラ共通：5方向 × 5部位</h1><p>冒険者・ゴブリン・無地の下地をすべて5方向へ統一。各25枚、計75枚。左右反転で8方向を描画します。<br>ファイル番号は1=正面、2=斜め前、3=横、4=背面、5=斜め後ろ。下の表示は回転順です。<br>冒険者・ゴブリンは256px透過PNG、下地の入力版は512px薄灰背景。ゲームには同じ基準寸法で登録します。</p><nav><select onchange="document.querySelectorAll('article').forEach(c=>c.hidden=this.value!=='all'&&c.dataset.kind!==this.value)"><option value="all">全キャラ</option><option value="adventurer">冒険者</option><option value="goblin">ゴブリン</option><option value="neutral_base">無地の下地</option></select><a href="../5方向素材の登録.md">5方向の規約</a><a href="../anima_i2iセット.zip">一式ZIP</a></nav><section class="grid">'''+''.join(cards)+'''</section></main><script>async function copyPrompt(b){const t=b.parentElement.querySelector('textarea');t.focus();t.select();try{if(navigator.clipboard&&window.isSecureContext){await navigator.clipboard.writeText(t.value);b.textContent='コピーしました'}else{b.textContent=document.execCommand('copy')?'コピーしました':'Ctrl+Cでコピー'}}catch(e){b.textContent='Ctrl+Cでコピー'}}</script></html>'''
(KIT/'index.html').write_text(page,encoding='utf-8')
(KIT/'衣装参考.html').write_text(page,encoding='utf-8')
(KIT/'プロンプト一覧.md').write_text('# 5方向素材・プロンプト一覧\n\n| キャラ | 部位 | 方向 | 画像 | 指示 |\n| --- | --- | --- | --- | --- |\n'+'\n'.join(links)+'\n',encoding='utf-8')
(KIT/'README.md').write_text('''# 全キャラ共通・5方向 i2iセット

[画像とプロンプト](index.html) ／ [登録規約](../5方向素材の登録.md)

冒険者・ゴブリン・無地の下地は、すべて頭・上半身・腰・片腕・片脚を各5方向、25枚ずつ用意しています。一式75枚。4方向は標準から廃止しました。

番号は1=正面、2=斜め前、3=横、4=背面、5=斜め後ろ。ギャラリーの表示は回転順なので5の後に4を表示します。

PNGをi2iへ読み込み、対応する短い文章の髪・色・衣装の記述を変えて使います。冒険者とゴブリンは256pxの透過版。下地は512pxの薄灰背景版と透過版があります。スクリーンショットをi2i入力に使わずPNGを使ってください。ローカル生成環境が透過を黒く扱う場合は単色背景へ合成してください。

全素材を毎回作る必要はありません。衣装の一部だけなら変更するモジュールの5方向だけ作り、残りは登録済み素材を流用できます。顔の目・眉・口だけを追加する場合は別途の簡易顔ルールに従い、5方向の描き直しは不要です。

Anima自体での実生成は未検証です。輪郭が変わりすぎる場合は生成の変化量を下げて調整します。ゲーム用の登録とi2i原画の差し替えは別作業です。
''',encoding='utf-8')
(DOC/'参照シート.html').write_text('<!doctype html><html lang="ja"><meta charset="utf-8"><meta http-equiv="refresh" content="0;url=anima_i2i/index.html"><a href="anima_i2i/index.html">全キャラの5方向参照シート</a></html>',encoding='utf-8')
with zipfile.ZipFile(DOC/'anima_i2iセット.zip','w',zipfile.ZIP_DEFLATED) as z:
    for f in KIT.rglob('*'):
        if f.is_file() and not f.name.endswith('.import'):z.write(f,str(Path('anima_i2i')/f.relative_to(KIT)))
print('Updated five-view manuals and all 75 input gallery entries.')
