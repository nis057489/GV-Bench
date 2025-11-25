from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional


@dataclass
class PeerView:
    """A single view belonging to a specific peer robot."""

    peer_id: int
    image_path: Path
    is_helpful: bool

    def to_dict(self) -> Dict[str, Any]:
        return {
            "peer_id": self.peer_id,
            "image_path": str(self.image_path),
            "is_helpful": self.is_helpful,
        }

    @staticmethod
    def from_dict(obj: Dict[str, Any]) -> "PeerView":
        return PeerView(
            peer_id=int(obj["peer_id"]),
            image_path=Path(obj["image_path"]),
            is_helpful=bool(obj["is_helpful"]),
        )


@dataclass
class Episode:
    """One kidnapped-robot scenario consisting of a query image and peer views."""

    episode_id: int
    sequence_name: str
    query_image: Path
    peers: List[PeerView]
    metadata: Optional[Dict[str, Any]] = None

    def num_helpful_peers(self) -> int:
        return sum(1 for peer in self.peers if peer.is_helpful)

    def to_dict(self) -> Dict[str, Any]:
        data: Dict[str, Any] = {
            "episode_id": self.episode_id,
            "sequence_name": self.sequence_name,
            "query_image": str(self.query_image),
            "peers": [peer.to_dict() for peer in self.peers],
        }
        if self.metadata is not None:
            data["metadata"] = self.metadata
        return data

    @staticmethod
    def from_dict(obj: Dict[str, Any]) -> "Episode":
        metadata = obj.get("metadata")
        return Episode(
            episode_id=int(obj["episode_id"]),
            sequence_name=obj["sequence_name"],
            query_image=Path(obj["query_image"]),
            peers=[PeerView.from_dict(peer) for peer in obj.get("peers", [])],
            metadata=metadata,
        )


@dataclass
class EpisodeDataset:
    """Container for a collection of kidnapped-robot episodes."""

    sequence_name: str
    episodes: List[Episode]

    def __len__(self) -> int:
        return len(self.episodes)

    def to_json_serializable(self) -> Dict[str, Any]:
        return {
            "sequence_name": self.sequence_name,
            "episodes": [episode.to_dict() for episode in self.episodes],
        }

    @staticmethod
    def from_json_dict(obj: Dict[str, Any]) -> "EpisodeDataset":
        return EpisodeDataset(
            sequence_name=obj["sequence_name"],
            episodes=[Episode.from_dict(item) for item in obj.get("episodes", [])],
        )
