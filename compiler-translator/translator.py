import json
import math
import sys
from z3 import Optimize, Int, Or, sat

def ceil_log2(n: int):
    if n <= 1:
        return 0
    return math.ceil(math.log2(n))

def parse_spec(spec: dict):
    length = int(spec["length"])
    field_specs = {}

    for item in spec["fields"]:
        for name, raw_size in item.items():
            key = name.upper()
            if raw_size.startswith(">="):
                field_specs[key] = {"min_size": int(raw_size[2:]), "fixed": False}
            else:
                field_specs[key] = {"min_size": int(raw_size), "fixed": True}

    formats = spec["instructions"]
    format_bits = max(1, ceil_log2(len(formats)))

    nodes = ["F"]
    sizes = {"F": format_bits}
    fixed = {"F": True}

    for name, info in field_specs.items():
        nodes.append(name)
        sizes[name] = info["min_size"]
        fixed[name] = info["fixed"]

    formats_data = []
    format_node_lists = []

    for fmt_id, fmt in enumerate(formats):
        operands = [x.upper() for x in fmt["operands"]]
        insns = fmt["insns"]

        opcode_bits = ceil_log2(len(insns))
        opcode_node = None

        fmt_nodes = ["F"] + operands

        if opcode_bits > 0:
            opcode_node = f"OP_{fmt_id}"
            nodes.append(opcode_node)
            sizes[opcode_node] = opcode_bits
            fixed[opcode_node] = True
            fmt_nodes.append(opcode_node)

        formats_data.append({
            "id": fmt_id,
            "format": fmt["format"],
            "operands": operands,
            "insns": insns,
            "opcode_bits": opcode_bits,
            "opcode_node": opcode_node,
        })
        format_node_lists.append(fmt_nodes)

    return {
        "length": length,
        "nodes": nodes,
        "sizes": sizes,
        "fixed": fixed,
        "formats_data": formats_data,
        "format_node_lists": format_node_lists,
    }

def build_overlap_graph(nodes, format_node_lists):
    graph = {n: set() for n in nodes}
    for fmt_nodes in format_node_lists:
        for i in range(len(fmt_nodes)):
            for j in range(i + 1, len(fmt_nodes)):
                a = fmt_nodes[i]
                b = fmt_nodes[j]
                graph[a].add(b)
                graph[b].add(a)
    return graph

def search_best_layout_z3(length, nodes, sizes, fixed, overlap_graph):
    solver = Optimize()

    starts = {n: Int(f"{n}_start") for n in nodes}
    szs = {n: Int(f"{n}_size") for n in nodes}

    for n in nodes:
        solver.add(starts[n] >= 0)
        solver.add(szs[n] >= sizes[n])
        if fixed[n]:
            solver.add(szs[n] == sizes[n])
        solver.add(starts[n] + szs[n] <= length)

    seen_pairs = set()
    for n1 in nodes:
        for n2 in overlap_graph[n1]:
            if n1 < n2:
                pair = (n1, n2)
                if pair not in seen_pairs:
                    solver.add(Or(
                        starts[n1] + szs[n1] <= starts[n2],
                        starts[n2] + szs[n2] <= starts[n1]
                    ))
                    seen_pairs.add(pair)

    flexible_nodes = [n for n in nodes if not fixed[n]]
    if flexible_nodes:
        objective = sum(szs[n] for n in flexible_nodes)
        solver.maximize(objective)

    solver.minimize(sum(starts[n] for n in nodes))

    if solver.check() == sat:
        m = solver.model()
        layout = {}
        for n in nodes:
            st_val = m[starts[n]].as_long()
            sz_val = m[szs[n]].as_long()
            layout[n] = (st_val, sz_val)
        return layout
    else:
        return None

def to_bit_range(length, start, size):
    msb = length - start - 1
    lsb = length - start - size
    return msb, lsb

def get_format_gaps(length, fmt_nodes, layout):
    used = []
    for node in fmt_nodes:
        start, size = layout[node]
        msb, lsb = to_bit_range(length, start, size)
        used.append({"node": node, "msb": msb, "lsb": lsb})

    used.sort(key=lambda x: -x["msb"])
    
    gaps = []
    current_bit = length - 1

    for fld in used:
        if current_bit > fld["msb"]:
            gaps.append((current_bit, fld["msb"] + 1))
        current_bit = fld["lsb"] - 1

    if current_bit >= 0:
        gaps.append((current_bit, 0))
        
    return used, gaps

def field_name_from_node(node):
    if node == "F":
        return "F"
    if node.startswith("OP_"):
        return "OPCODE"
    return node.upper()

def build_output(spec_info, layout):
    length = spec_info["length"]
    formats_data = spec_info["formats_data"]
    format_node_lists = spec_info["format_node_lists"]
    out = []

    global_gaps = set()
    fmt_used_list = []
    fmt_gaps_list = []

    for fmt_nodes in format_node_lists:
        used, gaps = get_format_gaps(length, fmt_nodes, layout)
        fmt_used_list.append(used)
        fmt_gaps_list.append(gaps)
        for g in gaps:
            global_gaps.add(g)

    global_gaps = sorted(list(global_gaps), key=lambda x: -x[0])
    gap_name_map = {g: f"RES{i}" for i, g in enumerate(global_gaps)}

    for fmt_data, used, gaps in zip(formats_data, fmt_used_list, fmt_gaps_list):
        template = list(used)
        for g in gaps:
            template.append({
                "name": gap_name_map[g],
                "msb": g[0],
                "lsb": g[1]
            })
        
        template.sort(key=lambda x: -x["msb"])

        for insn_id, insn_name in enumerate(fmt_data["insns"]):
            insn_obj = {"insn": insn_name, "fields": []}
            for item in template:
                if "node" in item:
                    name = field_name_from_node(item["node"])
                    width = item["msb"] - item["lsb"] + 1
                    if item["node"] == "F":
                        value = format(fmt_data["id"], f"0{width}b")
                    elif item["node"].startswith("OP_"):
                        value = format(insn_id, f"0{width}b")
                    else:
                        value = "+"
                else:
                    name = item["name"]
                    width = item["msb"] - item["lsb"] + 1
                    value = "0" * width

                insn_obj["fields"].append({
                    name: {
                        "msb": item["msb"],
                        "lsb": item["lsb"],
                        "value": value,
                    }
                })
            out.append(insn_obj)
    return out

def solve(input_path, output_path):
    with open(input_path, "r", encoding="utf-8") as f:
        spec = json.load(f)

    spec_info = parse_spec(spec)
    overlap_graph = build_overlap_graph(spec_info["nodes"], spec_info["format_node_lists"])

    layout = search_best_layout_z3(
        spec_info["length"],
        spec_info["nodes"],
        spec_info["sizes"],
        spec_info["fixed"],
        overlap_graph,
    )

    if layout is None:
        raise RuntimeError("UNSAT")

    output = build_output(spec_info, layout)

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=4)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: ./translator.py <input.json> <output.json>")
        sys.exit(1)

    solve(sys.argv[1], sys.argv[2])

