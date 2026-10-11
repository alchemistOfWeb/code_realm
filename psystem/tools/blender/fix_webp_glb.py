# Godot требует у текстуры поле "source"; Blender при WebP-экспорте пишет его только в EXT_texture_webp.
import json, struct, sys
for path in sys.argv[1:]:
    data = open(path, "rb").read()
    magic, ver, length = struct.unpack_from("<III", data, 0)
    jlen, jtype = struct.unpack_from("<II", data, 12)
    js = json.loads(data[20:20 + jlen].decode("utf-8"))
    rest = data[20 + jlen:]
    n = 0
    for t in js.get("textures", []):
        ext = t.get("extensions", {}).get("EXT_texture_webp")
        if ext is not None and "source" not in t:
            t["source"] = ext["source"]
            n += 1
    # Текстуры без изображения (в исходнике не было файла): убрать ссылки из материалов
    bad = {i for i, t in enumerate(js.get("textures", [])) if "source" not in t}
    for i in bad:
        js["textures"][i]["source"] = 0
    for m in js.get("materials", []):
        for key in ("normalTexture", "occlusionTexture", "emissiveTexture"):
            if m.get(key, {}).get("index") in bad:
                m.pop(key)
        pbr = m.get("pbrMetallicRoughness", {})
        for key in ("baseColorTexture", "metallicRoughnessTexture"):
            if pbr.get(key, {}).get("index") in bad:
                pbr.pop(key)
    if bad:
        print("  removed broken textures", sorted(bad))
    req = js.get("extensionsRequired", [])
    if "EXT_texture_webp" in req:
        req.remove("EXT_texture_webp")
        if not req:
            js.pop("extensionsRequired")
    out = json.dumps(js, separators=(",", ":")).encode("utf-8")
    out += b" " * ((4 - len(out) % 4) % 4)
    body = struct.pack("<II", len(out), jtype) + out + rest
    open(path, "wb").write(struct.pack("<III", magic, ver, 12 + len(body)) + body)
    print(path, "patched", n)
