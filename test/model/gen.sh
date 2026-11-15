#!/bin/sh
# Fixture-only generator: turn the model JSON into a tiny C header/impl.
# Not a product; it proves the exported declaration layer is sufficient.
set -eu
model="$1"; out="$2"
python3 - "$model" "$out" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
out = sys.argv[2]
box = next(s for s in m["structs"] if s["name"].endswith("Box"))
kind = next(e for e in m["enums"] if e["name"].endswith("Kind"))
with open(out + ".h", "w") as f:
    f.write("/* generated from ct.model; fixture only */\n")
    f.write("enum Kind {\n")
    for i, mem in enumerate(kind["members"]):
        comma = "," if i + 1 < len(kind["members"]) else ""
        f.write("    %s = %d%s\n" % (mem["name"], mem["value"], comma))
    f.write("};\n")
    f.write("struct Box {\n")
    for fld in box["fields"]:
        ty = fld["type"].replace("enum demo_Kind", "enum Kind")
        f.write("    %s %s;\n" % (ty, fld["name"]))
    f.write("};\n")
    f.write("int box_gen_sum(void);\n")
with open(out + ".c", "w") as f:
    f.write('#include "%s.h"\n' % out.split("/")[-1])
    f.write("int box_gen_sum(void) { return KIND_LARGE + 1; }\n")
PY
