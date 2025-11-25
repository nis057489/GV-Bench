from __future__ import annotations

import cv2
import numpy as np


class SimpleORBMatcher:
    """Minimal matcher compatible with the GV-Bench MODEL(img0, img1) API."""

    def __init__(self, max_num_keypoints: int = 2048, ratio_threshold: float = 0.75) -> None:
        self.max_num_keypoints = max_num_keypoints
        self.ratio_threshold = ratio_threshold
        self.detector = cv2.ORB_create(nfeatures=max_num_keypoints)
        self.matcher = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=False)

    def __call__(self, img0: np.ndarray, img1: np.ndarray) -> int:
        gray0 = self._ensure_grayscale(img0)
        gray1 = self._ensure_grayscale(img1)

        keypoints0, desc0 = self.detector.detectAndCompute(gray0, None)
        keypoints1, desc1 = self.detector.detectAndCompute(gray1, None)
        if desc0 is None or desc1 is None:
            return 0

        matches = self.matcher.knnMatch(desc0, desc1, k=2)
        good_matches = []
        for pair in matches:
            if len(pair) < 2:
                continue
            m, n = pair
            if m.distance < self.ratio_threshold * n.distance:
                good_matches.append(m)

        if len(good_matches) < 4:
            return 0

        pts0 = np.float32([keypoints0[m.queryIdx].pt for m in good_matches]).reshape(-1, 1, 2)
        pts1 = np.float32([keypoints1[m.trainIdx].pt for m in good_matches]).reshape(-1, 1, 2)
        _, inlier_mask = cv2.findHomography(pts0, pts1, cv2.RANSAC, 3.0)
        if inlier_mask is None:
            return 0
        return int(inlier_mask.sum())

    @staticmethod
    def _ensure_grayscale(image: np.ndarray) -> np.ndarray:
        if image.ndim == 2:
            return image
        if image.ndim == 3 and image.shape[2] == 1:
            return image[:, :, 0]
        return cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
