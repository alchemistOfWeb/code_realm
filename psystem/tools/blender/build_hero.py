# Запуск внутри Blender (Scripting): exec(open('build_hero.py').read()); build('Male', '.../hero_male.glb')
# W — папка с распакованными паками Quaternius (Universal Base Characters, Modular Character Outfits).
# После экспорта: python fix_webp_glb.py hero_*.glb (Godot требует поле source у WebP-текстур).
# Сборка героя CodeRealm в Blender: один скелет (UE-совместимый, 65 костей) + все варианты частей.
# В Godot части включаются видимостью: Outfit_Peasant_*, Outfit_Ranger_*, Hair_*, Race_ElfEars, Race_OrcTusks.
import bpy, bmesh, os, math, mathutils

W = r"PATH/TO/quaternius_packs"
OUTFITS = W + "/outfits/Exports/glTF (Godot-Unreal)/Outfits/"
BASE = W + "/base/Base Characters/Godot - UE/"
HAIR = W + "/base/Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/"
HAIRSTYLES = {
    "Male": ["Hair_Buzzed", "Hair_SimpleParted", "Hair_Long", "Hair_Beard"],
    "Female": ["Hair_Long", "Hair_Buns", "Hair_BuzzedFemale", "Hair_SimpleParted"],
}


def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.armatures, bpy.data.actions, bpy.data.materials, bpy.data.images):
        for item in list(coll):
            if item.users == 0:
                coll.remove(item)


def import_gltf(path):
    before = set(o.name for o in bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path, disable_bone_shape=True)
    return [bpy.data.objects[n] for n in set(o.name for o in bpy.data.objects) - before]


def adopt(objs, arm, prefix=None):
    """Перепривязать меши к основному скелету, лишние скелеты удалить."""
    for o in objs:
        if o.type == 'MESH':
            mw = o.matrix_world.copy()
            o.parent = arm
            o.matrix_world = mw
            for m in o.modifiers:
                if m.type == 'ARMATURE':
                    m.object = arm
            if prefix:
                o.name = prefix + o.name.split("_", 2)[-1] if "_" in o.name else prefix + o.name
    for o in objs:
        if o.type == 'ARMATURE' and o != arm:
            bpy.data.objects.remove(o, do_unlink=True)


def nearest_uv(head, point):
    """UV вершины головы, ближайшей к точке (для однотонной кожи на ушах)."""
    me = head.data
    uv_layer = me.uv_layers.active.data
    best, best_d = None, 1e9
    for poly in me.polygons:
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            d = (head.matrix_world @ v - point).length
            if d < best_d:
                best_d, best = d, uv_layer[li].uv.copy()
    return best


def skinned_mesh(name, bm, arm, material, uv=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = arm
    vg = obj.vertex_groups.new(name="Head")
    vg.add(list(range(len(me.vertices))), 1.0, 'REPLACE')
    mod = obj.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm
    me.materials.append(material)
    if uv is not None:
        layer = me.uv_layers.new(name="UVMap")
        for d in layer.data:
            d.uv = uv
    for p in me.polygons:
        p.use_smooth = True
    return obj


# Смещение лица относительно мужской головы (у женской модели голова ниже и чуть уже)
FACE = {"Male": (0.0, 1.0), "Female": (-0.042, 0.975)}


def make_ear(side, head, arm, skin, dz=0.0, sx=1.0):
    """Эльфийское ухо: вытянутый лист, кончик вверх-назад-наружу."""
    s = 1 if side > 0 else -1
    pts = [(0.086, 0.004, 1.636), (0.089, -0.004, 1.664), (0.094, 0.006, 1.700),
           (0.128, 0.052, 1.768), (0.098, 0.030, 1.694), (0.091, 0.026, 1.652)]
    bm = bmesh.new()
    front = [bm.verts.new((s * x * sx, y, z + dz)) for x, y, z in pts]
    back = [bm.verts.new((s * (x * sx - 0.012), y + 0.006, z + dz)) for x, y, z in pts]
    back = back  # толщина 1.2 см
    bm.faces.new(front if s > 0 else list(reversed(front)))
    bm.faces.new(list(reversed(back)) if s > 0 else back)
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([front[i], front[j], back[j], back[i]] if s > 0 else [back[i], back[j], front[j], front[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=1, use_grid_fill=True)
    return skinned_mesh("Race_ElfEar_" + ("L" if s > 0 else "R"), bm, arm, skin)


def make_tusk(side, arm, material, dz=0.0, sx=1.0):
    s = 1 if side > 0 else -1
    bm = bmesh.new()
    base = mathutils.Vector((s * 0.022 * sx, -0.082, 1.610 + dz))
    tip = mathutils.Vector((s * 0.029 * sx, -0.097, 1.646 + dz - (1 - sx) * 0.3))
    bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=0.0065 * sx, radius2=0.0012, depth=(tip - base).length)
    rot = (tip - base).to_track_quat('Z', 'Y').to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=mathutils.Matrix.Translation((base + tip) / 2) @ rot, verts=bm.verts)
    return skinned_mesh("Race_OrcTusk_" + ("L" if s > 0 else "R"), bm, arm, material)


def make_horn(side, arm, material, hb):
    """Рог тифлинга: изогнутая трубка от лба назад-вверх."""
    s = 1 if side > 0 else -1
    pts = [(0.036, -0.070, 0.092), (0.044, -0.068, 0.140), (0.056, -0.050, 0.188),
           (0.070, -0.012, 0.222), (0.082, 0.036, 0.234), (0.088, 0.082, 0.214)]
    radii = [0.021, 0.019, 0.015, 0.011, 0.006, 0.0015]
    pts = [mathutils.Vector((s * x, y, z + hb)) for x, y, z in pts]
    bm = bmesh.new()
    rings = []
    seg = 10
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        q = d.to_track_quat('Z', 'Y')
        ring = []
        for k in range(seg):
            a = 2 * math.pi * k / seg
            off = q @ mathutils.Vector((math.cos(a) * radii[i], math.sin(a) * radii[i], 0))
            ring.append(bm.verts.new(p + off))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(seg):
            j = (k + 1) % seg
            bm.faces.new([rings[i][k], rings[i][j], rings[i + 1][j], rings[i + 1][k]])
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return skinned_mesh("Race_Horn_" + ("L" if s > 0 else "R"), bm, arm, material)


def build(gender, out_path):
    clear()
    peasant = import_gltf(OUTFITS + gender + "_Peasant.gltf")
    arm = [o for o in peasant if o.type == 'ARMATURE'][0]
    arm.name = "Armature"
    for o in peasant:
        if o.type == 'MESH':
            o.name = "Outfit_Peasant_" + o.name.split("Peasant_", 1)[-1]
    ranger = import_gltf(OUTFITS + gender + "_Ranger.gltf")
    for o in ranger:
        if o.type == 'MESH':
            o.name = "Outfit_Ranger_" + o.name.split("Ranger_", 1)[-1]
    adopt(ranger, arm)

    # Голова, глаза и брови с базового тела
    base = import_gltf(BASE + "Superhero_" + gender + "_FullBody.gltf")
    body = [o for o in base if o.type == 'MESH' and o.name.lower().startswith("superhero")][0]
    keep = {body.vertex_groups[n].index for n in ("Head", "neck_01") if n in body.vertex_groups}
    bm = bmesh.new()
    bm.from_mesh(body.data)
    deform = bm.verts.layers.deform.active
    dead = []
    for v in bm.verts:
        w = v[deform]
        if not w or max(w.items(), key=lambda kv: kv[1])[0] not in keep:
            dead.append(v)
    bmesh.ops.delete(bm, geom=dead, context='VERTS')
    bm.to_mesh(body.data)
    bm.free()
    body.name = "Head"
    skin = bpy.data.materials.get("MI_Regular_" + gender)
    body.data.materials.clear()
    body.data.materials.append(skin)
    for o in base:
        if o.type == 'MESH' and o.name.startswith("Eye"):
            o.name = "Eyebrows" if "brow" in o.name.lower() else "Eyes"
    adopt(base, arm)

    # Причёски и борода
    for hair in HAIRSTYLES[gender]:
        objs = import_gltf(HAIR + hair + ".gltf")
        for o in objs:
            if o.type == 'MESH':
                o.name = hair
        adopt(objs, arm)

    # Расовые части
    tusk_mat = bpy.data.materials.new("MI_Tusk")
    tusk_mat.use_nodes = True
    tusk_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.9, 0.85, 0.7, 1)
    tusk_mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.5
    ear_mat = bpy.data.materials.new("MI_Ear_Skin")
    ear_mat.use_nodes = True
    ear_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.62, 0.36, 0.25, 1)
    ear_mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.6
    horn_mat = bpy.data.materials.new("MI_Horn")
    horn_mat.use_nodes = True
    horn_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.16, 0.11, 0.10, 1)
    horn_mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.35
    hb = {"Male": 1.657, "Female": 1.617}[gender]   # высота кончика носа
    dz, sx = FACE[gender]
    for side in (1, -1):
        make_horn(side, arm, horn_mat, hb)
        make_ear(side, body, arm, ear_mat, dz, sx)
        make_tusk(side, arm, tusk_mat, dz, sx)

    # Текстуры: цвет 1024, карты нормалей/ORM 512 — иначе файл весит ~80 МБ
    for img in bpy.data.images:
        if img.size[0] == 0:
            continue
        target = 1024 if "BaseColor" in img.name or "Eye" in img.name else 512
        if img.size[0] > target:
            img.scale(target, target)

    # Экспорт
    bpy.ops.object.select_all(action='DESELECT')
    for o in bpy.data.objects:
        o.select_set(True)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB', use_selection=True,
                              export_animations=False, export_skins=True, export_yup=True,
                              export_image_format='WEBP', export_image_quality=88)
    return sorted(o.name for o in bpy.data.objects)
