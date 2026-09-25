"""Deterministic extraction of generated rear artwork and source registration setup."""
from pathlib import Path
import json, shutil, html
import numpy as np
import cv2
from PIL import Image

ROOT=Path(__file__).resolve().parents[3]
KIT=ROOT/'docs/素材制作テンプレート/anima_i2i/neutral_base'
OUT=ROOT/'mini/layered2d/data/characters/neutral_base'
OUT.mkdir(parents=True,exist_ok=True)
raw=Image.open(KIT/'rear_source.png').convert('RGBA')
a=np.array(raw)
n,labels,stats,_=cv2.connectedComponentsWithStats((a[:,:,3]>250).astype('uint8'))
parts=[(i,s) for i,s in enumerate(stats) if i and s[4]>1500]
assert len(parts)==5
parts.sort(key=lambda x: x[1][1])
parts=[parts[0],parts[1],parts[3],parts[2],parts[4]]
modules=['heads','upper_body','lower_body','arms','legs']
prefixes=['01_head','02_upper_body','03_lower_body','04_arm','05_leg']
oldviews=['01_front','02_quarter','03_side','04_back']
manifest=json.loads((KIT/'manifest.json').read_text(encoding='utf-8'))
manifest['parts']=[p for p in manifest['parts'] if not p['file'].endswith('05_rear_quarter')]
for j,(idx,s) in enumerate(parts):
    x,y,w,h=map(int,s[:4])
    # Transparent shadow RGB from the generator is not artwork.
    support=cv2.dilate((labels==idx).astype('uint8'),np.ones((3,3),'uint8'))
    data=a.copy();data[support==0,3]=0
    img=Image.fromarray(data).crop((x-2,y-2,x+w+2,y+h+2))
    reference=Image.open(KIT/'transparent'/f'{prefixes[j]}_01_front.png').convert('RGBA')
    rect=reference.getbbox()
    scale=(rect[3]-rect[1])/img.height
    img=img.resize((round(img.width*scale),round(img.height*scale)),Image.Resampling.LANCZOS)
    canvas=Image.new('RGBA',(512,512));canvas.alpha_composite(img,((512-img.width)//2,(512-img.height)//2))
    name=f'{prefixes[j]}_05_rear_quarter'
    canvas.save(KIT/'transparent'/f'{name}.png')
    flat=Image.new('RGBA',(512,512),'#e5e7eb');flat.alpha_composite(canvas);flat.convert('RGB').save(KIT/'input'/f'{name}.png')
    front=(KIT/'prompts'/f'{prefixes[j]}_01_front.txt').read_text(encoding='utf-8')
    prompt=front.replace('正面から見た姿。','画面左を向いて奥へ背を向ける斜め後ろ、135度の向き。背中と側面が見える。顔の目・口は見せない。')
    (KIT/'prompts'/f'{name}.txt').write_text(prompt,encoding='utf-8')
    manifest['parts'].append({'file':name,'label':['頭・顔','上半身','腰・骨盤','片腕・手','片脚・足'][j]+' · 斜め後ろ','module':prefixes[j],'prompt':prompt})
    folder=OUT/'sources'/modules[j];folder.mkdir(parents=True,exist_ok=True)
    for v,suffix in enumerate(oldviews+['05_rear_quarter']):
        shutil.copy2(KIT/'transparent'/f'{prefixes[j]}_{suffix}.png',folder/f'single-{v+1}.png')
manifest['source_directions']=['front','front_three_quarter_left','left','back','back_three_quarter_left']
(KIT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
page=(KIT/'index.html').read_text(encoding='utf-8')
if 'id="rear-views"' not in page:
    cards=[]
    for p in manifest['parts'][-5:]:
        name=p['file'];cards.append(f'<article><h3>{p["label"]}</h3><a href="input/{name}.png"><img src="input/{name}.png"></a><p><a download href="input/{name}.png">i2i入力 PNG</a> / <a download href="transparent/{name}.png">透過 PNG</a></p><textarea>{html.escape(p["prompt"])}</textarea><button onclick="copyPrompt(this)">コピー</button></article>')
    page=page.replace('</main>','<h2 id="rear-views">追加：斜め後ろ</h2><p>single-5として登録。正面・斜め前・横・背面の4枚は番号を変えません。</p><section class="grid">'+''.join(cards)+'</section></main>')
    (KIT/'index.html').write_text(page,encoding='utf-8')
config=json.loads((ROOT/'mini/projected2d/b_cutout/expressions/simple_face/adventurer/template.json').read_text(encoding='utf-8'))
base='res://mini/layered2d/data/characters/neutral_base'
config.update(id='neutral_base_five_view_v1',display_name='無地の下地（5方向）',source_directions=manifest['source_directions'],sources={m:base+'/sources/'+m for m in modules},atlas_path=base+'/atlas.png')
config['head_landmarks']=[[.34,.66,.45,.5,.62,.5,.79,.5,.90] for _ in range(5)]
config['neck_sample']=[.46,.94,.07,.03]
config['slices'].update(head=[0,.91],chest=[0,1],abdomen=[0,.25],pelvis=[.10,.78],upper_arm=[0,.44],forearm=[.37,.80],hand=[.75,1],elbow=[.33,.48],thigh=[0,.43],shin=[.32,.85],boot=[.80,1],knee=[.29,.46])
config['surface']['boot']['radii']=[.12,.075,.17]
config['surface']['elbow']['radii']=[.065,.065,.065]
config['surface']['knee']['radii']=[.09,.09,.09]
config['surface']['pelvis']['radii']=[.30,.16,.23]
config['face']={'mode':'baked','atlas_path':base+'/atlas.png','registered':{'slots':[],'presets':{'neutral':{}}}}
config['notes']=['Five authored views; single-5 is rear three quarter. Opposite rear is reflected.','Face is baked: no expression/face part replacement until registered.','Derived head crown is still a back crop, not newly authored top artwork.']
# Refreshing source artwork must not undo the registered body proportions/cuts.
current_path=OUT/'template.json'
if current_path.exists():
    current=json.loads(current_path.read_text(encoding='utf-8'))
    for field in ('profile','surface','slices','joint_patches','seam_fade','rounded_joins','joint_anchors','neutral_stand'):
        if field in current: config[field]=current[field]
(OUT/'source_template.json').write_text(json.dumps(config,ensure_ascii=False,indent=2),encoding='utf-8')
print('25 source inputs and neutral source template prepared.')
