"""Split generated sprite packs. Original four source images remain untouched."""
from pathlib import Path
import json, shutil, html
import cv2
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[3]
PACK=ROOT/'mini/layered2d/output/five_view_migration'
KIT=ROOT/'docs/素材制作テンプレート/anima_i2i'
MODULES=['heads','upper_body','lower_body','arms','legs']
PREFIX=['01_head','02_upper_body','03_lower_body','04_arm','05_leg']
NAMES=['頭','上半身','腰・骨盤','片腕','片脚']
registry=json.loads((ROOT/'mini/layered2d/data/catalog.json').read_text(encoding='utf-8'))
for ci,name in enumerate(['adventurer','goblin']):
    config=json.loads((ROOT/registry['templates'][ci].replace('res://','')).read_text(encoding='utf-8'))
    a=np.array(Image.open(PACK/f'{name}_rear_raw.png').convert('RGBA'))
    n,l,s,_=cv2.connectedComponentsWithStats((a[:,:,3]>250).astype('uint8'))
    parts=[(i,r) for i,r in enumerate(s) if i and r[4]>1500]
    assert len(parts)==5,(name,len(parts))
    parts.sort(key=lambda p: int(p[1][1]+p[1][3]/2)//512*2+int(p[1][0]+p[1][2]/2)//512)
    preview=Image.new('RGBA',(256*5,256),'#e5e7eb')
    for j,(idx,r) in enumerate(parts):
        x,y,w,h=map(int,r[:4]);mask=cv2.dilate((l==idx).astype('uint8'),np.ones((3,3),'uint8'))
        data=a.copy();data[mask==0,3]=0
        cropped=Image.fromarray(data).crop((x-2,y-2,x+w+2,y+h+2))
        folder=ROOT/config['sources'][MODULES[j]].replace('res://','')
        reference=Image.open(folder/'single-4.png').convert('RGBA');box=reference.getbbox()
        scale=min((box[3]-box[1])/cropped.height,(reference.width-12)/cropped.width)
        cropped=cropped.resize((round(cropped.width*scale),round(cropped.height*scale)),Image.Resampling.LANCZOS)
        canvas=Image.new('RGBA',reference.size)
        canvas.alpha_composite(cropped,((reference.width-cropped.width)//2,round((box[1]+box[3]-cropped.height)/2)))
        canvas.save(folder/'single-5.png')
        preview.alpha_composite(canvas,(j*256,0))
        stem=PREFIX[j]+'_05_rear_quarter'
        shutil.copy2(folder/'single-5.png',KIT/name/f'{stem}.png')
        desc=f'{NAMES[j]}だけ。既存の{name}と同じ配色・衣装を保つ。画面左を向いて奥へ背を向ける斜め後ろ、135度の視点。背中と側面を描き、顔の目や口は見せない。入力の長さ・幅・位置・接合位置を保つ。シンプルな2Dセル塗り、無地の薄灰背景。文字や他の部位は描かない。'
        (KIT/name/f'{stem}.txt').write_text(desc+'\n',encoding='utf-8')
    preview.convert('RGB').save(PACK/f'{name}_rear_preview.png')
print('Added dedicated rear-quarter parts to both existing characters.')
