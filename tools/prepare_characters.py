"""Builds assets/characters/ from the Quaternius "Universal Base Characters" Standard kit (CC0).

Usage:
    python tools/prepare_characters.py "<path to the unzipped 'Universal Base Characters[Standard]' folder>"

What it does
  - copies the male and female bodies and the hair, beard and brow meshes under short names
  - removes the texture references from the glTF files (the game assigns materials in code)
  - resizes the 2048 px textures to 1024 px, lightens the skin so one texture can be tinted to
    every skin tone, and writes five eye colors

Needs Python 3 with Pillow and numpy. The output is already committed, so this only has to be
run again when the source kit changes.
"""
import json
import os
import shutil
import sys

import numpy as np
from PIL import Image

SRC = sys.argv[1]
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "characters")
TEX = os.path.join(OUT, "tex")
os.makedirs(TEX, exist_ok=True)

BODY = os.path.join(SRC, "Base Characters", "Godot - UE")
HAIR = os.path.join(SRC, "Hairstyles", "Origin at 0", "glTF (Godot)")

MODELS = {
    "male": os.path.join(BODY, "Superhero_Male_FullBody"),
    "female": os.path.join(BODY, "Superhero_Female_FullBody"),
    "hair_buzzed": os.path.join(HAIR, "Hair_Buzzed"),
    "hair_buzzed_f": os.path.join(HAIR, "Hair_BuzzedFemale"),
    "hair_parted": os.path.join(HAIR, "Hair_SimpleParted"),
    "hair_long": os.path.join(HAIR, "Hair_Long"),
    "hair_buns": os.path.join(HAIR, "Hair_Buns"),
    "beard": os.path.join(HAIR, "Hair_Beard"),
    "brows_regular": os.path.join(HAIR, "Eyebrows_Regular"),
    "brows_female": os.path.join(HAIR, "Eyebrows_Female"),
}


def convert_model(name, src):
    with open(src + ".gltf", encoding="utf-8") as f:
        doc = json.load(f)
    assert len(doc["buffers"]) == 1
    doc["buffers"][0]["uri"] = name + ".bin"
    # Materials keep their names; textures are assigned by the game.
    for key in ("images", "textures", "samplers"):
        doc.pop(key, None)
    for mat in doc.get("materials", []):
        pbr = mat.get("pbrMetallicRoughness", {})
        pbr.pop("baseColorTexture", None)
        pbr.pop("metallicRoughnessTexture", None)
        for key in ("normalTexture", "occlusionTexture", "emissiveTexture"):
            mat.pop(key, None)
    with open(os.path.join(OUT, name + ".gltf"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(doc, f, separators=(",", ":"))
    shutil.copyfile(src + ".bin", os.path.join(OUT, name + ".bin"))
    print("model", name, [m["name"] for m in doc["meshes"]], [m["name"] for m in doc.get("materials", [])])


def save(img, name):
    img.save(os.path.join(TEX, name), optimize=True)
    print("texture", name, img.size)


def resized(path, size=1024):
    return Image.open(path).convert("RGB").resize((size, size), Image.LANCZOS)


def skin(path, name):
    # Lighten toward a fair olive base. Darker tones are made in the game by multiplying.
    a = np.asarray(resized(path), dtype=np.float32) / 255.0
    a = np.clip(a * np.array([1.12, 1.3, 1.5], dtype=np.float32), 0.0, 1.0)
    save(Image.fromarray((a * 255.0 + 0.5).astype(np.uint8)), name)


def eyes(path):
    # The iris is the only strongly saturated dark-orange area. Shift its hue and value.
    src = Image.open(path).convert("RGB")
    hsv = np.asarray(src.convert("HSV"), dtype=np.float32)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    yy, xx = np.mgrid[0:src.size[1], 0:src.size[0]]
    cx, cy, r = 0.5 * src.size[0], 0.745 * src.size[1], 0.115 * src.size[0]
    iris = ((xx - cx) ** 2 + (yy - cy) ** 2) < r * r
    # name: (hue 0-255, saturation scale, value scale)
    colors = {
        "eye_0.png": (20.0, 1.0, 0.55),   # dark brown
        "eye_1.png": (None, 1.0, 1.0),    # brown (as shipped)
        "eye_2.png": (30.0, 0.85, 1.15),  # hazel
        "eye_3.png": (75.0, 0.6, 1.0),    # green
        "eye_4.png": (150.0, 0.25, 1.2),  # grey
    }
    for name, (hue, sat, val) in colors.items():
        out = hsv.copy()
        if hue is not None:
            out[..., 0] = np.where(iris, hue, h)
        out[..., 1] = np.where(iris, np.clip(s * sat, 0, 255), s)
        out[..., 2] = np.where(iris, np.clip(v * val, 0, 255), v)
        save(Image.fromarray(out.astype(np.uint8), "HSV").convert("RGB"), name)


for model_name, model_src in MODELS.items():
    convert_model(model_name, model_src)

skin(os.path.join(BODY, "T_Superhero_Male_Dark.png"), "skin_male.png")
skin(os.path.join(BODY, "T_Superhero_Female_Dark_BaseColor.png"), "skin_female.png")
save(resized(os.path.join(BODY, "T_Superhero_Male_Normal.png")), "normal_male.png")
save(resized(os.path.join(BODY, "T_Superhero_Female_Normal.png")), "normal_female.png")
save(resized(os.path.join(HAIR, "T_Hair_1_BaseColor.png")), "hair_1.png")
save(resized(os.path.join(HAIR, "T_Hair_2_BaseColor.png")), "hair_2.png")
save(resized(os.path.join(HAIR, "T_Hair_1_Normal.png")), "hair_1_normal.png")
save(resized(os.path.join(HAIR, "T_Hair_2_Normal.png")), "hair_2_normal.png")
eyes(os.path.join(BODY, "T_Eye_Brown.png"))
print("done ->", OUT)
