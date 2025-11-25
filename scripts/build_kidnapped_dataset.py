#!/usr/bin/env python3
"""CLI for constructing kidnapped-robot episode datasets from GV-Bench sequences."""

# Example:
# python scripts/build_kidnapped_dataset.py \
#   --config config/day.yaml \
#   --images_root dataset/images \
#   --output artifacts/kidnapped_day.json \
#   --max_episodes 100 \
#   --num_distractor_peers 4

import argparse
import sys
from pathlib import Path

# Ensure local packages remain importable when invoked as a standalone script.
PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from kidnapped_bench.builder import build_episodes_from_gvbench, save_episode_dataset


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build kidnapped-robot benchmark episodes")
    parser.add_argument(
        "--config",
        type=Path,
        required=True,
        help="Path to GV-Bench configuration YAML (e.g. config/day.yaml)",
    )
    parser.add_argument(
        "--images_root",
        type=Path,
        required=True,
        help="Directory containing GV-Bench images (e.g. dataset/images)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="Output JSON file for the generated episode dataset",
    )
    parser.add_argument("--max_episodes", type=int, default=None, help="Limit the number of generated episodes")
    parser.add_argument(
        "--num_distractor_peers",
        type=int,
        default=4,
        help="Number of distractor peers to sample per episode",
    )
    parser.add_argument("--seed", type=int, default=0, help="Random seed for reproducible sampling")
    parser.add_argument(
        "--include_negative_pairs",
        action="store_true",
        help="Include negative GV-Bench pairs (defaults to positive pairs only)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    dataset = build_episodes_from_gvbench(
        config_path=args.config,
        images_root=args.images_root,
        max_episodes=args.max_episodes,
        num_distractor_peers=args.num_distractor_peers,
        positive_only=not args.include_negative_pairs,
        random_seed=args.seed,
    )
    save_episode_dataset(dataset, args.output)


if __name__ == "__main__":
    main()
