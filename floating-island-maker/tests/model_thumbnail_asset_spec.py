#!/usr/bin/env python3
"""Filesystem gate for the generated built-in model thumbnail set."""

from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "asset-tools" / "generate_model_thumbnails.py"
spec = spec_from_file_location("generate_model_thumbnails", GENERATOR)
assert spec and spec.loader
module = module_from_spec(spec)
spec.loader.exec_module(module)

models = module.export_models()
assert len({model["thumbnail"] for model in models}) == 69
assert module.validate(models) < 260 * 1024
print("model_thumbnail_asset_spec: ok")
