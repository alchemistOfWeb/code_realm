# Копирует выбранные glTF-модели китов Quaternius в проект, уменьшая текстуры.
import json, os, shutil, sys
from PIL import Image
W = sys.argv[1]
DST = sys.argv[2]
KITS = {
    "nature": (W + "/nature/glTF", None),
    "props": (W + "/props/Exports/glTF", [
        "Anvil", "Barrel", "Barrel_Apples", "Bench", "Bookcase_2", "Book_Stack_1", "Bucket_Wooden_1", "Cage_Small",
        "Candle_1", "CandleStick_Triple", "Cauldron", "Chain_Coil", "Chest_Wood", "Coin_Pile", "Coin_Pile_2",
        "Crate_Metal", "Crate_Wooden", "Dummy", "FarmCrate_Apple", "Key_Gold", "Lantern_Wall", "Pot_1", "Potion_1",
        "Potion_2", "Potion_4", "Pouch_Large", "Rope_1", "Scroll_1", "Scroll_2", "Shelf_Simple", "Shield_Wooden",
        "Stall_Cart_Empty", "Stall_Empty", "Stool", "Sword_Bronze", "Table_Large", "Torch_Metal", "Vase_2", "Vase_4",
        "Vase_Rubble_Medium", "WeaponStand", "Workbench", "Banner_1", "Banner_2", "Bag", "Chandelier", "Axe_Bronze",
        "Pickaxe_Bronze", "BookStand", "Mug"]),
    "village": (W + "/village/glTF", [
        "Wall_UnevenBrick_Straight", "Wall_UnevenBrick_Door_Round", "Wall_UnevenBrick_Window_Wide_Round", "Wall_Arch",
        "Wall_Plaster_Straight", "Wall_Plaster_Door_Round", "Wall_Plaster_Window_Wide_Round", "Corner_Exterior_Brick",
        "Corner_Exterior_Wood", "Floor_UnevenBrick", "Floor_WoodDark", "Roof_RoundTiles_4x4", "Roof_RoundTiles_6x6",
        "Roof_Tower_RoundTiles", "Prop_Wagon", "Prop_WoodenFence_Single", "Prop_WoodenFence_Extension1",
        "Prop_MetalFence_Ornament", "Prop_Crate", "Prop_Chimney", "Prop_Support", "Prop_Vine1", "Prop_Vine2",
        "Stairs_Exterior_Straight", "Door_1_Round", "DoorFrame_Round_Brick", "Window_Wide_Round1",
        "Prop_ExteriorBorder_Straight1", "Prop_Brick1", "Prop_Brick2"]),
}
total = 0
for kit, (src, names) in KITS.items():
    out = os.path.join(DST, kit)
    os.makedirs(out, exist_ok=True)
    if names is None:
        names = [f[:-5] for f in os.listdir(src) if f.endswith(".gltf") and not f.startswith("Petal")]
    textures = set()
    for n in names:
        g = os.path.join(src, n + ".gltf")
        if not os.path.exists(g):
            print("missing", kit, n); continue
        data = json.load(open(g, encoding="utf-8"))
        shutil.copy(g, out)
        for b in data.get("buffers", []):
            shutil.copy(os.path.join(src, b["uri"]), out)
        for im in data.get("images", []):
            textures.add(im["uri"])
    for t in sorted(textures):
        p = os.path.join(src, t)
        if not os.path.exists(p):
            print("missing tex", t); continue
        im = Image.open(p)
        lim = 512 if any(k in t for k in ("Normal", "ORM", "Roughness")) else 1024
        if max(im.size) > lim:
            im = im.resize((lim, lim * im.size[1] // im.size[0]), Image.LANCZOS)
        im.save(os.path.join(out, t), optimize=True)
    size = sum(os.path.getsize(os.path.join(out, f)) for f in os.listdir(out))
    total += size
    print(kit, len(names), "models,", len(textures), "textures,", size // 1024, "KB")
print("total", total // 1024, "KB")
