"""Custom matcher registry for GV-Bench.

This module exposes lightweight matchers that follow the
``image-matching-models`` contract so they can be used inside
``config/*.yaml`` files alongside the upstream models.
"""

from collections import OrderedDict
from typing import Dict, Iterable

from .orb import OpenCVORBMatcher

# Mapping of matcher key -> callable constructor
_CUSTOM_MATCHERS: Dict[str, type] = OrderedDict(
    {
        "orb-opencv": OpenCVORBMatcher,
    }
)

CUSTOM_AVAILABLE_MODELS: Iterable[str] = tuple(_CUSTOM_MATCHERS.keys())


def list_custom_matchers() -> Iterable[str]:
    """Return matcher keys that can be referenced in config files."""

    return CUSTOM_AVAILABLE_MODELS


def get_custom_matcher(name: str, *, device: str = "cpu", **kwargs):
    """Instantiate a custom matcher by key.

    Parameters
    ----------
    name: str
        Name of the matcher (as written in the YAML config).
    device: str
        Torch device string. Most custom matchers run on CPU but we
        accept any torch device for interface parity.
    kwargs: dict
        Additional keyword arguments forwarded to the matcher
        constructor. ``main.py`` forwards the RANSAC kwargs through this
        path so we normalize them before instantiation.
    """

    if name not in _CUSTOM_MATCHERS:
        available = ", ".join(_CUSTOM_MATCHERS)
        raise ValueError(f"Unknown custom matcher '{name}'. Options: {available}")

    matcher_cls = _CUSTOM_MATCHERS[name]
    ransac_params = kwargs.pop("ransac_kwargs", {})
    if isinstance(ransac_params, dict):
        kwargs.update(ransac_params)
    return matcher_cls(device=device, **kwargs)
