# FBX → glTF из Blender: материалы получили альфу 0 и режим MASK — делаем их непрозрачными.
import json, struct, sys
for path in sys.argv[1:]:
    data = open(path, "rb").read()
    magic, ver, length = struct.unpack_from("<III", data, 0)
    jlen, jtype = struct.unpack_from("<II", data, 12)
    js = json.loads(data[20:20 + jlen].decode("utf-8"))
    rest = data[20 + jlen:]
    for m in js.get("materials", []):
        m.pop("alphaMode", None)
        m.pop("alphaCutoff", None)
        pbr = m.setdefault("pbrMetallicRoughness", {})
        f = pbr.get("baseColorFactor", [1, 1, 1, 1])
        pbr["baseColorFactor"] = f[:3] + [1.0]
        pbr.setdefault("roughnessFactor", 0.7)
    out = json.dumps(js, separators=(",", ":")).encode("utf-8")
    out += b" " * ((4 - len(out) % 4) % 4)
    body = struct.pack("<II", len(out), jtype) + out + rest
    open(path, "wb").write(struct.pack("<III", magic, ver, 12 + len(body)) + body)
print("patched", len(sys.argv) - 1)
