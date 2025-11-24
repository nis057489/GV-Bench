from typing import Tuple, Any, Dict
import numpy as np
from prettytable import PrettyTable
from sklearn.metrics import average_precision_score, precision_recall_curve
import yaml
import argparse
from dataloaders.ImagePairDataset import ImagePairDataset
import warnings
import torch
from torch.utils.data import DataLoader
from tqdm import tqdm
from matching import get_matcher, available_models
from matching.im_models.base_matcher import BaseMatcher
from matching.viz import *
import sys
from pathlib import Path

# import image-matching-models early so it precedes any pip install
IMM_PATH = 'third_party/image-matching-models'
if IMM_PATH not in sys.path:
    sys.path.insert(0, IMM_PATH)


warnings.filterwarnings("ignore")


def parser():
    parser = argparse.ArgumentParser()
    parser.add_argument('config', type=str, nargs='?',
                        help='Path to the config file')
    parser.add_argument('--support_model', action='store_true',
                        help="Show all image-matching models")
    args = parser.parse_args()

    def dict2namespace(config):
        namespace = argparse.Namespace()
        for key, value in config.items():
            if isinstance(value, dict):
                new_value = dict2namespace(value)
            else:
                new_value = value
            setattr(namespace, key, new_value)
        return namespace

    # Check for config file
    if args.config is None:
        if args.support_model:
            print(f"Available models: {available_models}")
            sys.exit(0)
        else:
            raise ValueError('Please provide a config file')

    # Load the config file
    try:
        with open(args.config, 'r') as f:
            config = yaml.safe_load(f)
    except FileNotFoundError:
        raise FileNotFoundError(f"Config file '{args.config}' not found.")
    except yaml.YAMLError as e:
        raise ValueError(f"Error parsing YAML file: {e}")

    config = dict2namespace(config)

    return config

# wrapper of image-matching-models BaseMatcher's load image


def load_image(path: str | Path, resize: int | Tuple = None, rot_angle: float = 0) -> torch.Tensor:
    return BaseMatcher.load_image(path, resize, rot_angle)


def match(matcher, loader, image_size=512):
    '''
    Args:
        matcher: image-matching-models matcher
        loader: dataloader
        image_size: int, resized shape

    Return:
        scores: np.array
    '''
    scores = []
    for idx, data in tqdm(enumerate(loader), total=len(loader)):
        img0, img1 = data['img0'], data['img1']
        img0 = img0.squeeze(0)
        img1 = img1.squeeze(0)
        result = matcher(img0, img1)
        num_inliers, H, mkpts0, mkpts1 = result['num_inliers'], result[
            'H'], result['inlier_kpts0'], result['inlier_kpts1']
        scores.append(num_inliers)
    # normalize
    scores = np.array(scores)
    scores_norm = (scores - np.min(scores)) / (np.max(scores) - np.min(scores))
    return scores_norm

# max recall @ 100% precision


def max_recall(precision: np.ndarray, recall: np.ndarray):
    idx = np.where(precision == 1.0)
    max_recall = np.max(recall[idx])
    return max_recall


def eval(scores, labels):
    '''
    Args:
        scores: np.array
        labels: np.array
        matcher: name of matcher
        talbe: PrettyTable holder

    Return:
        precision: np.array
        recall: np.array

    '''
    # mAP
    average_precision = average_precision_score(labels, scores)
    precision, recall, TH = precision_recall_curve(labels, scores)
    # max recall @ 100% precision
    recall_max = max_recall(precision, recall)
    return average_precision, recall_max


def _parse_matcher_entry(entry: Any) -> tuple[str, Dict[str, Any]]:
    """Normalize matcher entries that can be either strings or {name, params}."""
    if isinstance(entry, str):
        return entry, {}
    if isinstance(entry, dict):
        matcher_name = entry.get('name')
        if matcher_name is None:
            raise ValueError("Matcher entry dict must include a 'name' field")
        params = entry.get('params') or {}
        if not isinstance(params, dict):
            raise ValueError("Matcher 'params' must be a dictionary")
        return matcher_name, params
    raise TypeError(f"Unsupported matcher entry type: {type(entry)}")


def main(config):
    # ransac params, keep it consistent for fairness
    ransac_kwargs = {'ransac_reproj_thresh': 3,
                     'ransac_conf': 0.95,
                     'ransac_iters': 2000}  # optional ransac params
    # bench sequence
    gvbench_seq = ImagePairDataset(config.data, transform=None)  # load images
    # current imm models only support batch size 1
    gvbench_loader = DataLoader(gvbench_seq, batch_size=1, shuffle=False,
                                num_workers=10, pin_memory=True, prefetch_factor=10)  # create dataloader
    labels = gvbench_seq.label  # load labels
    # create result table
    table = PrettyTable()
    table.title = f"GV-Bench:{config.data.name}"
    table.field_names = ["Matcher", "mAP", "Max Recall@1.0"]

    # Check if the file exists and write headers only once
    log_path = Path(getattr(config, 'exp_log',
                    f"{config.data.name}_results.log"))
    log_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        with open(log_path, "x") as file:  # "x" mode creates the file; raises an error if it exists
            # Format the headers
            headers = "| " + " | ".join(table.field_names) + " |"
            file.write(headers + "\n")  # Write headers
            file.write("-" * len(headers) + "\n")  # Optional: Add a separator
    except FileExistsError:
        pass  # File already exists, so we skip writing headers

    # matching loop
    for matcher_entry in config.matcher:
        matcher_name, matcher_kwargs = _parse_matcher_entry(matcher_entry)
        assert matcher_name in available_models, f"Invalid model name. Choose from {available_models}"

        matcher_kwargs = dict(matcher_kwargs)  # shallow copy before mutation
        if 'device' in matcher_kwargs:
            warnings.warn("'device' is controlled by GV-Bench and will be ignored in matcher params")
            matcher_kwargs.pop('device')

        print(f"Running {matcher_name}...")
        # load matcher
        if torch.cuda.is_available():
            matcher_config = {**ransac_kwargs, **matcher_kwargs}
            model = get_matcher(matcher_name, device='cuda', **matcher_config)
        else:
            raise ValueError('No GPU available')
        # compute scores
        scores = match(model, gvbench_loader, image_size=(
            config.data.image_height, config.data.image_width))
        mAP, MaxR = eval(scores, labels)

        # write to log
        table.add_row([matcher_name, mAP, MaxR])
        # Append the new row to the file
        with open(log_path, "a") as file:  # Open in append mode
            row = table._rows[-1]  # Get the last row added
            formatted_row = "| " + \
                " | ".join(map(str, row)) + " |"  # Format the row
            file.write(formatted_row + "\n")  # Write the formatted row

    # print result
    print(table)


if __name__ == "__main__":
    # parser
    cfg = parser()
    main(cfg)
