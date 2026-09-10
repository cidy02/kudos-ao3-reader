"""The canvas-reading helpers `redesign-spec-outline.py` defines, importable.

The outline script's filename has hyphens in it, so it cannot be imported; this
re-exports the three pieces the inventory script needs by loading it by path.
Keeping one implementation matters more than the small indirection — an artboard
splitter that disagreed with the outline tool's would make the two disagree
about what artboard something is in.
"""

import importlib.util
import os

_OUTLINE_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "redesign-spec-outline.py"
)
_spec = importlib.util.spec_from_file_location("redesign_spec_outline", _OUTLINE_PATH)
_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_module)

DEFAULT_CANVAS = _module.DEFAULT_CANVAS
artboard_blocks = _module.artboard_blocks
read_canvas = _module.read_canvas
strip_markup = _module.strip_markup
