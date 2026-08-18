#!/usr/bin/env python3
"""Generate tiny deterministic isometric previews for built-in Lua models."""

from __future__ import annotations

import argparse
import glob
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
EXPORTER = ROOT / "asset-tools" / "generate_model_thumbnails.lua"
OUTPUT_DIR = ROOT / "assets" / "image" / "model-thumbs"
SIZE = 48
AA = 4


def fengari_command() -> list[str]:
    explicit = os.environ.get("FENGARI")
    if explicit:
        return [explicit]
    installed = shutil.which("fengari")
    if installed:
        return [installed]
    candidates = glob.glob(str(Path.home() / ".npm" / "_npx" / "*" / "node_modules" / ".bin" / "fengari"))
    if candidates:
        candidates.sort(key=lambda path: os.path.getmtime(path), reverse=True)
        return [candidates[0]]
    npx = shutil.which("npx")
    if npx:
        return [npx, "-y", "-p", "fengari-node-cli", "fengari"]
    raise RuntimeError("fengari not found; install fengari-node-cli or set FENGARI")


def export_models() -> list[dict]:
    process = subprocess.run(
        [*fengari_command(), str(EXPORTER.relative_to(ROOT))],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    models: list[dict] = []
    by_id: dict[str, dict] = {}
    for raw_line in process.stdout.splitlines():
        fields = raw_line.split("\t")
        if not fields or fields[0] not in {"A", "B"}:
            continue
        if fields[0] == "A":
            if len(fields) != 6:
                raise RuntimeError(f"malformed asset line: {raw_line}")
            model = {
                "asset_id": fields[1], "thumbnail": fields[2], "name": fields[3],
                "category": fields[4], "expected_blocks": int(fields[5]), "blocks": [],
            }
            models.append(model)
            by_id[fields[1]] = model
        else:
            if len(fields) != 16 or fields[1] not in by_id:
                raise RuntimeError(f"malformed block line: {raw_line}")
            by_id[fields[1]]["blocks"].append({
                "position": tuple(float(value) for value in fields[3:6]),
                "size": tuple(max(0.01, float(value)) for value in fields[6:9]),
                "rotation": tuple(float(value) for value in fields[9:12]),
                "color": fields[12], "material": fields[13], "shape": fields[14],
                "collision": fields[15],
            })
    if len(models) != 69:
        raise RuntimeError(f"expected 69 built-in models, got {len(models)}")
    for model in models:
        if len(model["blocks"]) != model["expected_blocks"]:
            raise RuntimeError(f"block count mismatch for {model['asset_id']}")
    return models


def rotate(point: tuple[float, float, float], angles: tuple[float, float, float]) -> tuple[float, float, float]:
    x, y, z = point
    rx, ry, rz = angles
    cosine, sine = math.cos(rx), math.sin(rx)
    y, z = y * cosine - z * sine, y * sine + z * cosine
    cosine, sine = math.cos(ry), math.sin(ry)
    x, z = x * cosine + z * sine, -x * sine + z * cosine
    cosine, sine = math.cos(rz), math.sin(rz)
    x, y = x * cosine - y * sine, x * sine + y * cosine
    return x, y, z


def world_point(block: dict, point: tuple[float, float, float]) -> tuple[float, float, float]:
    x, y, z = rotate(point, block["rotation"])
    px, py, pz = block["position"]
    return x + px, y + py, z + pz


def project(point: tuple[float, float, float]) -> tuple[float, float, float]:
    x, y, z = point
    # Camera looks down from (+X,+Y,+Z). The vertical coefficient keeps tall
    # trees readable while preserving enough roof and ground-plane detail.
    return (x - z) * 0.70710678, (x + z) * 0.31 - y * 0.86, x + z + y * 0.52


def color_tuple(value: str, alpha: int = 255) -> tuple[int, int, int, int]:
    text = value.strip().lstrip("#")
    if len(text) != 6:
        text = "f2e7cf"
    try:
        return int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16), alpha
    except ValueError:
        return 242, 231, 207, alpha


def shade(color: tuple[int, int, int, int], amount: float) -> tuple[int, int, int, int]:
    return tuple(min(255, max(0, round(component * amount))) for component in color[:3]) + (color[3],)


def alpha_for(material: str) -> int:
    if material == "glass":
        return 148
    if material == "water":
        return 188
    return 255


def polygon_primitive(points: list[tuple[float, float, float]], fill, depth_offset: float = 0) -> dict:
    projected = [project(point) for point in points]
    return {
        "kind": "polygon", "points": [(point[0], point[1]) for point in projected],
        "depth": sum(point[2] for point in projected) / len(projected) + depth_offset,
        "fill": fill,
    }


def box_primitives(block: dict, base) -> list[dict]:
    sx, sy, sz = block["size"]
    local = [
        (-sx / 2, -sy / 2, -sz / 2), (sx / 2, -sy / 2, -sz / 2),
        (sx / 2, sy / 2, -sz / 2), (-sx / 2, sy / 2, -sz / 2),
        (-sx / 2, -sy / 2, sz / 2), (sx / 2, -sy / 2, sz / 2),
        (sx / 2, sy / 2, sz / 2), (-sx / 2, sy / 2, sz / 2),
    ]
    vertices = [world_point(block, point) for point in local]
    faces = [
        ((0, 1, 2, 3), 0.77), ((4, 7, 6, 5), 0.92),
        ((0, 4, 5, 1), 0.72), ((3, 2, 6, 7), 1.10),
        ((0, 3, 7, 4), 0.82), ((1, 5, 6, 2), 0.96),
    ]
    return [polygon_primitive([vertices[index] for index in indices], shade(base, light))
            for indices, light in faces]


def radial_primitives(block: dict, base, cone: bool = False) -> list[dict]:
    sx, sy, sz = block["size"]
    segments = 8
    bottom = [world_point(block, (math.cos(index * math.tau / segments) * sx / 2, -sy / 2,
                                  math.sin(index * math.tau / segments) * sz / 2))
              for index in range(segments)]
    top_radius = 0 if cone else 1
    top = [world_point(block, (math.cos(index * math.tau / segments) * sx / 2 * top_radius, sy / 2,
                               math.sin(index * math.tau / segments) * sz / 2 * top_radius))
           for index in range(segments)]
    primitives = [polygon_primitive(bottom, shade(base, 0.72))]
    if cone:
        apex = world_point(block, (0, sy / 2, 0))
        for index in range(segments):
            primitives.append(polygon_primitive(
                [bottom[index], bottom[(index + 1) % segments], apex],
                shade(base, 0.78 + (index % 4) * 0.08),
            ))
    else:
        primitives.append(polygon_primitive(top, shade(base, 1.10)))
        for index in range(segments):
            primitives.append(polygon_primitive(
                [bottom[index], bottom[(index + 1) % segments], top[(index + 1) % segments], top[index]],
                shade(base, 0.76 + (index % 4) * 0.07),
            ))
    return primitives


def prism_primitives(block: dict, base, tetra: bool = False) -> list[dict]:
    sx, sy, sz = block["size"]
    if tetra:
        local = [(-sx / 2, -sy / 2, -sz / 2), (sx / 2, -sy / 2, -sz / 2),
                 (0, -sy / 2, sz / 2), (0, sy / 2, 0)]
        faces = [(0, 1, 2), (0, 3, 1), (1, 3, 2), (2, 3, 0)]
    else:
        local = [(-sx / 2, -sy / 2, -sz / 2), (sx / 2, -sy / 2, -sz / 2),
                 (0, sy / 2, -sz / 2), (-sx / 2, -sy / 2, sz / 2),
                 (sx / 2, -sy / 2, sz / 2), (0, sy / 2, sz / 2)]
        faces = [(0, 2, 1), (3, 4, 5), (0, 1, 4, 3), (1, 2, 5, 4), (2, 0, 3, 5)]
    vertices = [world_point(block, point) for point in local]
    return [polygon_primitive([vertices[index] for index in face], shade(base, 0.78 + i * 0.07))
            for i, face in enumerate(faces)]


def shape_primitives(block: dict) -> list[dict]:
    base = color_tuple(block["color"], alpha_for(block["material"]))
    shape = block["shape"]
    if shape == "sphere":
        sx, sy, sz = block["size"]
        corners = [world_point(block, (x * sx / 2, y * sy / 2, z * sz / 2))
                   for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
        projected = [project(point) for point in corners]
        center = project(block["position"])
        return [{
            "kind": "ellipse",
            "points": [(min(point[0] for point in projected), min(point[1] for point in projected)),
                       (max(point[0] for point in projected), max(point[1] for point in projected))],
            "depth": center[2], "fill": base,
        }]
    if shape == "cylinder":
        return radial_primitives(block, base)
    if shape == "cone" or shape == "pyramid":
        return radial_primitives(block, base, cone=True)
    if shape == "tri_prism":
        return prism_primitives(block, base)
    if shape == "tetra":
        return prism_primitives(block, base, tetra=True)
    if shape == "torus":
        sx, sy, sz = block["size"]
        corners = [world_point(block, (x * sx / 2, y * sy / 2, z * sz / 2))
                   for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
        projected = [project(point) for point in corners]
        center = project(block["position"])
        return [{
            "kind": "ring",
            "points": [(min(point[0] for point in projected), min(point[1] for point in projected)),
                       (max(point[0] for point in projected), max(point[1] for point in projected))],
            "depth": center[2], "fill": base,
        }]
    return box_primitives(block, base)


def model_primitives(model: dict) -> list[dict]:
    primitives = []
    for block in model["blocks"]:
        primitives.extend(shape_primitives(block))
    primitives.sort(key=lambda primitive: primitive["depth"])
    return primitives


def render_model(model: dict, output: Path) -> None:
    primitives = model_primitives(model)
    all_points = [point for primitive in primitives for point in primitive["points"]]
    if not all_points:
        all_points = [(-0.5, -0.5), (0.5, 0.5)]
    min_x, max_x = min(point[0] for point in all_points), max(point[0] for point in all_points)
    min_y, max_y = min(point[1] for point in all_points), max(point[1] for point in all_points)
    span_x, span_y = max(0.01, max_x - min_x), max(0.01, max_y - min_y)
    logical_margin = 3.2
    scale = min((SIZE - logical_margin * 2) / span_x, (SIZE - logical_margin * 2) / span_y)
    offset_x = (SIZE - span_x * scale) * 0.5 - min_x * scale
    offset_y = (SIZE - span_y * scale) * 0.5 - min_y * scale

    image = Image.new("RGBA", (SIZE * AA, SIZE * AA), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image, "RGBA")

    def transform(point):
        return ((point[0] * scale + offset_x) * AA, (point[1] * scale + offset_y) * AA)

    # A tiny neutral contact shadow improves legibility without introducing a
    # background card or materially increasing PNG size.
    draw.ellipse((SIZE * AA * 0.20, SIZE * AA * 0.79, SIZE * AA * 0.80, SIZE * AA * 0.91),
                 fill=(39, 55, 67, 24))
    for primitive in primitives:
        points = [transform(point) for point in primitive["points"]]
        fill = primitive["fill"]
        outline = shade(fill, 0.68)[:3] + (min(fill[3], 150),)
        if primitive["kind"] == "polygon":
            draw.polygon(points, fill=fill, outline=outline, width=max(1, round(0.38 * AA)))
        elif primitive["kind"] == "ellipse":
            draw.ellipse((*points[0], *points[1]), fill=fill, outline=outline,
                         width=max(1, round(0.45 * AA)))
            x0, y0 = points[0]
            x1, y1 = points[1]
            draw.ellipse((x0 + (x1 - x0) * 0.19, y0 + (y1 - y0) * 0.13,
                          x0 + (x1 - x0) * 0.43, y0 + (y1 - y0) * 0.34),
                         fill=(255, 255, 255, min(52, fill[3])))
        else:
            width = max(1, round(min(abs(points[1][0] - points[0][0]),
                                     abs(points[1][1] - points[0][1])) * 0.22))
            draw.ellipse((*points[0], *points[1]), outline=fill, width=width)

    image = image.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    palette = image.quantize(colors=48, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    output.parent.mkdir(parents=True, exist_ok=True)
    palette.save(output, format="PNG", optimize=True, compress_level=9)


def expected_path(model: dict) -> Path:
    thumbnail = model["thumbnail"]
    prefix = "image/"
    if not thumbnail.startswith(prefix):
        raise RuntimeError(f"invalid thumbnail resource path for {model['asset_id']}: {thumbnail}")
    return ROOT / "assets" / thumbnail


def validate(models: list[dict]) -> int:
    paths = [expected_path(model) for model in models]
    if len(set(paths)) != 69:
        raise RuntimeError("thumbnail paths must be unique")
    total = 0
    for path in paths:
        if not path.is_file():
            raise RuntimeError(f"missing thumbnail: {path.relative_to(ROOT)}")
        with Image.open(path) as image:
            if image.size != (SIZE, SIZE) or image.format != "PNG":
                raise RuntimeError(f"invalid thumbnail format: {path.relative_to(ROOT)}")
            if "transparency" not in image.info and image.mode != "RGBA":
                raise RuntimeError(f"thumbnail has no transparency: {path.relative_to(ROOT)}")
        total += path.stat().st_size
    # 69 previews should stay substantially smaller than one normal 1024px
    # texture. This cap also catches accidental RGBA/unoptimised regeneration.
    if total > 260 * 1024:
        raise RuntimeError(f"thumbnail set is too large: {total} bytes")
    print(f"model_thumbnails: ok (69 files, {total} bytes, {total / 69:.0f} bytes average)")
    return total


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="validate without regenerating")
    args = parser.parse_args()
    models = export_models()
    if not args.check:
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        expected = {expected_path(model) for model in models}
        for stale in OUTPUT_DIR.glob("*.png"):
            if stale not in expected:
                stale.unlink()
        for model in models:
            render_model(model, expected_path(model))
    validate(models)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(f"model thumbnail generation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
