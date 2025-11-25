from __future__ import annotations

import hashlib
import json
import random
from argparse import Namespace
from collections import defaultdict
from pathlib import Path
from typing import Dict, Iterable, List, Optional

import yaml

from dataloaders.ImagePairDataset import ImagePairDataset

from .episodes import Episode, EpisodeDataset, PeerView


def _dict_to_namespace(config: Dict[str, object]) -> Namespace:
    namespace = Namespace()
    for key, value in config.items():
        if isinstance(value, dict):
            setattr(namespace, key, _dict_to_namespace(value))
        else:
            setattr(namespace, key, value)
    return namespace


def _stable_int_from_string(value: str) -> int:
    digest = hashlib.sha256(value.encode("utf-8")).hexdigest()
    return int(digest[:16], 16)


def infer_peer_id(image_path: Path) -> int:
    peer_name = image_path.parent.name
    return _stable_int_from_string(peer_name)


def _resolve_image_path(images_root: Path, image_reference: str | Path) -> Path:
    path = Path(image_reference)
    if path.is_absolute():
        return path
    return images_root / path


def _prepare_peer_index(image_paths: Iterable[Path]) -> Dict[int, List[Path]]:
    peer_to_images: Dict[int, List[Path]] = defaultdict(list)
    for path in image_paths:
        peer_id = infer_peer_id(path)
        peer_to_images[peer_id].append(path)
    return peer_to_images


def build_episodes_from_gvbench(
    config_path: Path,
    images_root: Path,
    max_episodes: Optional[int] = None,
    num_distractor_peers: int = 4,
    positive_only: bool = True,
    random_seed: int = 0,
) -> EpisodeDataset:
    images_root = Path(images_root).expanduser()
    if not images_root.exists():
        raise FileNotFoundError(f"Images root '{images_root}' does not exist")
    images_root = images_root.resolve()

    with Path(config_path).open("r", encoding="utf-8") as handle:
        config_dict = yaml.safe_load(handle)

    config_ns = _dict_to_namespace(config_dict)
    config_ns.data.image_dir = str(images_root)

    config_dir = Path(config_path).parent
    repo_root = Path(__file__).resolve().parents[1]
    pairs_info_path = Path(config_ns.data.pairs_info)
    if not pairs_info_path.is_absolute():
        candidate_paths = [config_dir / pairs_info_path, repo_root / pairs_info_path]
        resolved_path = None
        for candidate in candidate_paths:
            if candidate.exists():
                resolved_path = candidate.resolve()
                break
        if resolved_path is None:
            # Fall back to resolving relative to the config directory to preserve previous behavior.
            resolved_path = (config_dir / pairs_info_path).resolve()
        config_ns.data.pairs_info = str(resolved_path)

    dataset = ImagePairDataset(config_ns.data, transform=None)
    labels = list(dataset.label)
    sequence_name = getattr(config_ns.data, "name", Path(config_path).stem)

    all_image_refs = {Path(pair[0]) for pair in dataset.image_pairs}
    all_image_refs.update(Path(pair[1]) for pair in dataset.image_pairs)
    all_image_paths = [_resolve_image_path(images_root, ref) for ref in sorted(all_image_refs)]
    peer_index = _prepare_peer_index(all_image_paths)

    rng = random.Random(random_seed)
    episodes: List[Episode] = []

    for idx, (pair, label) in enumerate(zip(dataset.image_pairs, labels)):
        if positive_only and label != 1:
            continue

        img_rel0, img_rel1 = pair
        query_image = _resolve_image_path(images_root, img_rel0)
        peer_image = _resolve_image_path(images_root, img_rel1)
        helpful_peer_id = infer_peer_id(peer_image)

        peers: List[PeerView] = [
            PeerView(
                peer_id=helpful_peer_id,
                image_path=peer_image,
                is_helpful=bool(label),
            )
        ]
        used_paths = {peer_image}

        candidate_peer_ids = [pid for pid in sorted(peer_index.keys()) if pid != helpful_peer_id]
        if len(candidate_peer_ids) > num_distractor_peers:
            selected_peer_ids = rng.sample(candidate_peer_ids, num_distractor_peers)
        else:
            selected_peer_ids = candidate_peer_ids

        for peer_id in selected_peer_ids:
            candidates = [path for path in peer_index[peer_id] if path not in used_paths]
            if not candidates:
                continue
            chosen_path = rng.choice(candidates)
            used_paths.add(chosen_path)
            peers.append(
                PeerView(
                    peer_id=peer_id,
                    image_path=chosen_path,
                    is_helpful=False,
                )
            )

        episode = Episode(
            episode_id=len(episodes),
            sequence_name=sequence_name,
            query_image=query_image,
            peers=peers,
            metadata={
                "label": int(label),
                "orig_index": idx,
            },
        )
        episodes.append(episode)

        if max_episodes is not None and len(episodes) >= max_episodes:
            break

    return EpisodeDataset(sequence_name=sequence_name, episodes=episodes)


def save_episode_dataset(dataset: EpisodeDataset, path: Path) -> None:
    output_path = Path(path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as handle:
        json.dump(dataset.to_json_serializable(), handle, indent=2)


def load_episode_dataset(path: Path) -> EpisodeDataset:
    input_path = Path(path)
    with input_path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    return EpisodeDataset.from_json_dict(payload)


if __name__ == "__main__":
    import argparse
    import cv2

    from .custom_matcher import SimpleORBMatcher

    parser = argparse.ArgumentParser(description="Minimal kidnapped-bench sanity test")
    parser.add_argument("--config", type=Path, required=True, help="Path to GV-Bench YAML config")
    parser.add_argument(
        "--images_root",
        type=Path,
        required=True,
        help="Root directory containing GV-Bench images",
    )
    parser.add_argument(
        "--max_episodes",
        type=int,
        default=5,
        help="Maximum number of episodes to generate for the test run",
    )
    parser.add_argument(
        "--num_distractor_peers",
        type=int,
        default=4,
        help="Number of distractor peers to sample per episode",
    )
    parser.add_argument("--seed", type=int, default=0, help="Random seed for sampling")
    args = parser.parse_args()

    demo_dataset = build_episodes_from_gvbench(
        config_path=args.config,
        images_root=args.images_root,
        max_episodes=args.max_episodes,
        num_distractor_peers=args.num_distractor_peers,
        random_seed=args.seed,
    )

    print(f"Generated {len(demo_dataset)} episodes for sequence '{demo_dataset.sequence_name}'")
    for episode in demo_dataset.episodes:
        print(
            f"Episode {episode.episode_id}: query={episode.query_image} peers={len(episode.peers)} "
            f"helpful={episode.num_helpful_peers()}"
        )

    if demo_dataset.episodes:
        matcher = SimpleORBMatcher()
        first_episode = demo_dataset.episodes[0]
        query = cv2.imread(str(first_episode.query_image))
        if query is None:
            print("Warning: failed to load query image for matcher demo")
        else:
            print("Matcher sanity check (inlier counts):")
            for peer in first_episode.peers:
                peer_image = cv2.imread(str(peer.image_path))
                if peer_image is None:
                    print(f"  Peer {peer.peer_id}: failed to load {peer.image_path}")
                    continue
                inliers = matcher(query, peer_image)
                role = "helpful" if peer.is_helpful else "distractor"
                print(f"  Peer {peer.peer_id} ({role}): {inliers} inliers")
