import cv2
import numpy as np
import torch

from matching.im_models.base_matcher import BaseMatcher


class OpenCVORBMatcher(BaseMatcher):
    """Lightweight ORB baseline following the image-matching-models API."""

    def __init__(
        self,
        device: str = "cpu",
        max_num_keypoints: int = 2048,
        ratio_threshold: float = 0.75,
        fast_threshold: int = 20,
        **kwargs,
    ) -> None:
        ransac_params = kwargs.pop("ransac_kwargs", {})
        if isinstance(ransac_params, dict):
            kwargs.update(ransac_params)
        super().__init__(device=device, **kwargs)
        self.max_num_keypoints = max_num_keypoints
        self.ratio_threshold = ratio_threshold
        self.detector = cv2.ORB_create(nfeatures=max_num_keypoints, fastThreshold=fast_threshold)
        self.matcher = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=False)

    def _forward(self, img0: torch.Tensor, img1: torch.Tensor):
        gray0 = self._to_grayscale(img0)
        gray1 = self._to_grayscale(img1)

        keypoints0, desc0 = self.detector.detectAndCompute(gray0, None)
        keypoints1, desc1 = self.detector.detectAndCompute(gray1, None)

        if desc0 is None or desc1 is None or not keypoints0 or not keypoints1:
            return self._empty_output()

        matches = self.matcher.knnMatch(desc0, desc1, k=2)
        good_matches = []
        for pair in matches:
            if len(pair) < 2:
                continue
            m, n = pair
            if m.distance < self.ratio_threshold * n.distance:
                good_matches.append(m)

        if len(good_matches) < 4:
            return self._empty_output(keypoints0, keypoints1, desc0, desc1)

        mkpts0 = np.array([keypoints0[m.queryIdx].pt for m in good_matches], dtype=np.float32)
        mkpts1 = np.array([keypoints1[m.trainIdx].pt for m in good_matches], dtype=np.float32)

        all_kpts0 = self._keypoints_to_array(keypoints0)
        all_kpts1 = self._keypoints_to_array(keypoints1)
        desc0 = desc0.astype(np.float32, copy=False)
        desc1 = desc1.astype(np.float32, copy=False)

        return mkpts0, mkpts1, all_kpts0, all_kpts1, desc0, desc1

    def _empty_output(self, keypoints0=None, keypoints1=None, desc0=None, desc1=None):
        all_kpts0 = self._keypoints_to_array(keypoints0)
        all_kpts1 = self._keypoints_to_array(keypoints1)
        desc0 = self._descriptor_to_array(desc0)
        desc1 = self._descriptor_to_array(desc1)
        empty = np.empty((0, 2), dtype=np.float32)
        return empty, empty, all_kpts0, all_kpts1, desc0, desc1

    @staticmethod
    def _keypoints_to_array(keypoints):
        if not keypoints:
            return np.empty((0, 2), dtype=np.float32)
        return np.array([kp.pt for kp in keypoints], dtype=np.float32)

    @staticmethod
    def _descriptor_to_array(descriptor):
        if descriptor is None:
            return np.empty((0, 32), dtype=np.float32)
        return descriptor.astype(np.float32, copy=False)

    @staticmethod
    def _to_grayscale(image: torch.Tensor) -> np.ndarray:
        tensor = image.detach().cpu()
        tensor = tensor.mul(255.0).clamp(0, 255).byte()
        np_img = tensor.permute(1, 2, 0).numpy()
        if np_img.shape[2] == 1:
            return np_img[:, :, 0]
        return cv2.cvtColor(np_img, cv2.COLOR_RGB2GRAY)
