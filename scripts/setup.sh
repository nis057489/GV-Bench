#!/usr/bin/env bash
# Helper to set up GV-Bench dependencies, matchers, and optional SphereGlue stack.

set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: setup.sh [options]

Options:
  --torch-index URL      Override the PyTorch wheel index. Default: CUDA 12.4 wheels.
  --cpu                  Shortcut for --torch-index https://download.pytorch.org/whl/cpu
  --no-torch             Skip installing torch/torchvision (assumes they are present).
  --with-sphereglue      Install SphereGlue extras (torch-geometric stack).
  --full-extras          Install every optional matcher extra (same as [all]).
  -h, --help             Show this message.

Hints:
  * Run this script from the repo root inside the gvbench conda env.
  * Override TORCH_INDEX or TORCH_VERSION via env vars if you need a custom wheel.
EOF
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
TORCH_INDEX_DEFAULT="https://download.pytorch.org/whl/cu124"
TORCH_INDEX="${TORCH_INDEX:-$TORCH_INDEX_DEFAULT}"
INSTALL_TORCH=1
IMM_EXTRA_GROUP="loftrs,duster"
INSTALL_ALL_EXTRAS=0
SPHEREGLUE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --torch-index)
      TORCH_INDEX="$2"
      shift 2
      ;;
    --cpu)
      TORCH_INDEX="https://download.pytorch.org/whl/cpu"
      shift
      ;;
    --no-torch)
      INSTALL_TORCH=0
      shift
      ;;
    --with-sphereglue)
      SPHEREGLUE=1
      shift
      ;;
    --full-extras)
      INSTALL_ALL_EXTRAS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

pip_install() {
  python -m pip install "$@"
}

ensure_submodule() {
  if [[ -d "$ROOT_DIR/third_party/image-matching-models/.git" ]]; then
    return
  fi
  echo "[setup] Initializing image-matching-models submodule..."
  if ! git -C "$ROOT_DIR" submodule update --init --recursive; then
    echo "[setup] Submodule checkout failed; cloning fallback." >&2
    rm -rf "$ROOT_DIR/third_party/image-matching-models"
    git clone --branch gvbench https://github.com/jarvisyjw/image-matching-models.git \
      "$ROOT_DIR/third_party/image-matching-models"
    git -C "$ROOT_DIR/third_party/image-matching-models" submodule update --init --recursive
  fi
}

install_torch_stack() {
  if [[ $INSTALL_TORCH -eq 0 ]]; then
    echo "[setup] Skipping torch installation as requested."
    return
  fi
  echo "[setup] Installing torch + torchvision from $TORCH_INDEX"
  pip_install --upgrade pip
  pip_install --upgrade --index-url "$TORCH_INDEX" torch torchvision
}

install_root_reqs() {
  echo "[setup] Installing core GV-Bench requirements"
  pip_install -r "$ROOT_DIR/requirements.txt"
}

install_imm_packages() {
  local extras="${IMM_EXTRA_GROUP}"
  if [[ $INSTALL_ALL_EXTRAS -eq 1 ]]; then
    extras="all"
  elif [[ $SPHEREGLUE -eq 1 ]]; then
    extras+=" ,sphereglue"
  fi
  extras="$(echo "$extras" | tr -d ' ')"

  echo "[setup] Installing image-matching-models in editable mode"
  pip_install -e "$ROOT_DIR/third_party/image-matching-models"

  if [[ -n "$extras" ]]; then
    echo "[setup] Installing optional matcher extras: [$extras]"
    pip_install -e "$ROOT_DIR/third_party/image-matching-models[$extras]"
  fi
}

install_pyg_stack() {
  if [[ $SPHEREGLUE -eq 0 && $INSTALL_ALL_EXTRAS -eq 0 ]]; then
    return
  fi
  echo "[setup] Ensuring torch-geometric wheels match installed torch"
  local torch_version cuda_tag pyg_index
  torch_version="$(python -c "import torch; print(torch.__version__.split('+')[0])" 2>/dev/null || true)"
  cuda_tag="$(python -c "import torch; cuda = torch.version.cuda; print('cpu' if cuda is None else 'cu'+cuda.replace('.',''))" 2>/dev/null || true)"
  if [[ -z "$torch_version" || -z "$cuda_tag" ]]; then
    echo "[setup] Unable to determine torch version; skip torch-geometric helper." >&2
    return
  fi
  pyg_index="https://data.pyg.org/whl/torch-${torch_version}+${cuda_tag}.html"
  echo "[setup] Installing torch-geometric wheels from $pyg_index"
  pip_install torch-scatter torch-sparse torch-cluster torch-spline-conv torch-geometric \
    -f "$pyg_index"
}

main() {
  cd "$ROOT_DIR"
  ensure_submodule
  install_torch_stack
  install_root_reqs
  install_imm_packages
  install_pyg_stack
  echo "[setup] Done. Test with: python -c 'import torch, matching'"
}

main "$@"
