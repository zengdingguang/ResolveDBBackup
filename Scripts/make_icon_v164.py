#!/usr/bin/env python3
"""v1.6.4 图标处理：去水印 -> 白底转透明 -> 生成 MenuIcon.png / AppIcon-1024.png / AppIcon.icns。
用法: python3 Scripts/make_icon_v164.py
"""
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "Assets/icons/new_app_icon.png")
ICON_DIR = os.path.join(ROOT, "Scripts/icon")

img = Image.open(SRC).convert("RGBA")
W, H = img.size
print(f"源图: {W}x{H}")

# 1) 去除右下角"豆包AI生成"水印（纯白填充该区域）
# 水印 OCR box 千分比: (822,940)-(986,984)，放宽一点覆盖
x0, y0 = int(W * 0.78), int(H * 0.92)
x1, y1 = W, H
draw = ImageDraw.Draw(img)
draw.rectangle([x0, y0, x1, y1], fill=(255, 255, 255, 255))
print("水印区域已填充为白色")

# 2) 白底转透明：接近白色的像素 alpha=0，保留主体剪影
px = img.load()
removed = 0
for y in range(H):
    for x in range(W):
        r, g, b, a = px[x, y]
        if r > 240 and g > 240 and b > 240:
            px[x, y] = (r, g, b, 0)
            removed += 1
print(f"白底转透明: 处理 {removed} 像素")

os.makedirs(ICON_DIR, exist_ok=True)

# 3) 菜单栏图标（template 用，透明底黑色剪影，128px 足够）
menu = img.resize((128, 128), Image.LANCZOS)
menu.save(os.path.join(ICON_DIR, "MenuIcon.png"))
print("MenuIcon.png 已生成 (128x128, 透明底)")

# 4) App 图标（1024，带圆角遮罩，透明底）
size = 1024
app = img.resize((size, size), Image.LANCZOS)
mask = Image.new("L", (size, size), 0)
md = ImageDraw.Draw(mask)
radius = int(size * 0.22)
md.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
out.paste(app, (0, 0), mask)
out.save(os.path.join(ICON_DIR, "AppIcon-1024.png"))
print("AppIcon-1024.png 已生成 (1024x1024, 圆角透明底)")

# 5) 生成 iconset 并转 icns
iconset = os.path.join(ICON_DIR, "AppIcon.iconset")
os.makedirs(iconset, exist_ok=True)
sizes = {
    "icon_16x16.png": 16, "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32, "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128, "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256, "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512, "icon_512x512@2x.png": 1024,
}
for name, s in sizes.items():
    thumb = out.resize((s, s), Image.LANCZOS)
    thumb.save(os.path.join(iconset, name))
ret = os.system(f"iconutil -c icns {iconset} -o {os.path.join(ICON_DIR, 'AppIcon.icns')}")
print("iconutil 返回:", ret)
print("完成")
