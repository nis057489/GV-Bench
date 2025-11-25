#!/bin/bash

#PBS -N gvbench
#PBS -l ncpus=5
#PBS -l mem=16gb
#PBS -l ngpus=1
#PBS -l walltime=12:00:00
#PBS -J 1-6

set -e

# Set GPU FIRST before anything else
GPU_ID="${2:-0}"  # Second argument for manual runs
if [ -n "${PBS_ARRAY_INDEX}" ]; then
  # PBS sets CUDA_VISIBLE_DEVICES automatically, keep it
  GPU_ID="${CUDA_VISIBLE_DEVICES:-0}"
fi
export CUDA_VISIBLE_DEVICES="${GPU_ID}"

# Now determine paths
if [ -z "${PBS_O_WORKDIR}" ]; then
  SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  SCRATCH="/scratch/nijsmith/manual_run_$$"
  PBS_JOBID="manual_$$"
  RESULTS_DIR="${SOURCE_DIR}"
  ARRAY_INDEX="${1:-1}"
else
  SOURCE_DIR="${PBS_O_WORKDIR}"
  SCRATCH="/scratch/nijsmith/${PBS_JOBID%.*}_${PBS_ARRAY_INDEX}"
  RESULTS_DIR="${PBS_O_WORKDIR}"
  ARRAY_INDEX="${PBS_ARRAY_INDEX:-1}"
fi

echo "=========================================="
echo "Job started: $(date)"
echo "Job ID: ${PBS_JOBID}"
echo "Array Index: ${ARRAY_INDEX}"
echo "GPU: ${GPU_ID}"
echo "Source: ${SOURCE_DIR}"
echo "Scratch: ${SCRATCH}"
echo "=========================================="

# Map array index to config
CONFIGS=(
  "config/day.yaml"
  "config/night.yaml"
  "config/season.yaml"
  "config/weather.yaml"
  "config/nordland.yaml"
  "config/uacampus.yaml"
)
CONFIG="${CONFIGS[$((ARRAY_INDEX-1))]}"

if [ -z "$CONFIG" ] || [ ! -f "${SOURCE_DIR}/${CONFIG}" ]; then
  echo "ERROR: Invalid array index ${ARRAY_INDEX} or config not found"
  exit 1
fi

echo "Running config: ${CONFIG}"
echo "=========================================="

mkdir -p ${SCRATCH}
cd ${SOURCE_DIR}

# Setup image-matching-models if needed
if [ ! -d "${SOURCE_DIR}/third_party/image-matching-models/matching" ]; then
  echo "Setting up image-matching-models..."
  rm -rf ${SOURCE_DIR}/third_party/image-matching-models
  git clone --recursive https://github.com/jarvisyjw/image-matching-models.git ${SOURCE_DIR}/third_party/image-matching-models
fi

# Initialize submodules if empty
SUBMODULE_COUNT=$(find "${SOURCE_DIR}/third_party/image-matching-models/matching/third_party" -mindepth 2 -maxdepth 2 -type f 2>/dev/null | wc -l || echo "0")
if [ "$SUBMODULE_COUNT" -eq 0 ]; then
  echo "Initializing submodules..."
  cd "${SOURCE_DIR}/third_party/image-matching-models"
  git submodule update --init --recursive
  cd ${SOURCE_DIR}
fi

echo "Copying to scratch..."
rsync -a --info=progress2 \
  --exclude='dataset/images/' \
  --exclude='third_party/image-matching-models/.git/' \
  --exclude='__pycache__/' \
  --exclude='*.pyc' \
  --exclude='.git/' \
  --exclude='results/' \
  --exclude='*.log' \
  ${SOURCE_DIR}/ ${SCRATCH}/

# Copy cached models
[ -d "${SOURCE_DIR}/.cache" ] && cp -r ${SOURCE_DIR}/.cache ${SCRATCH}/
[ -d "${SOURCE_DIR}/third_party/image-matching-models/matching/model_weights" ] && \
  rsync -a ${SOURCE_DIR}/third_party/image-matching-models/matching/model_weights/ \
    ${SCRATCH}/third_party/image-matching-models/matching/model_weights/

# Extract dataset images in scratch
if [ -d "${SOURCE_DIR}/dataset/images" ]; then
  echo "Extracting dataset images..."
  mkdir -p ${SCRATCH}/dataset/images
  rsync -a --info=progress2 ${SOURCE_DIR}/dataset/images/*.zip ${SCRATCH}/dataset/images/
  cd ${SCRATCH}/dataset/images
  for zip in *.zip; do
    [ -f "$zip" ] && (unzip -q "$zip" && rm "$zip") &
  done
  wait
else
  echo "WARNING: Dataset not found. Download from:"
  echo "https://hkustconnect-my.sharepoint.com/:f:/g/personal/jyubt_connect_ust_hk/EkflAPp79spCviRK5EkSGVABrGncg-TfNV5I3ThXxzopLg?e=DdwCAL"
fi

cd ${SCRATCH}

echo "=========================================="
echo "Setting up environment..."
echo "=========================================="

# Install/setup conda
if ! command -v conda &> /dev/null; then
  echo "Installing Miniconda..."
  wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ${SCRATCH}/miniconda.sh
  bash ${SCRATCH}/miniconda.sh -b -p ${SCRATCH}/miniconda3
  rm ${SCRATCH}/miniconda.sh
  eval "$(${SCRATCH}/miniconda3/bin/conda shell.bash hook)"
  conda config --set auto_activate_base false
else
  eval "$(conda shell.bash hook)"
fi

# Create environment
conda create -n gvbench python=3.11 -y
conda activate gvbench

# Install dependencies
pip install -q -r requirements.txt
[ -f "third_party/image-matching-models/requirements.txt" ] && \
  pip install -q -r third_party/image-matching-models/requirements.txt

# Verify GPU is available
echo "Checking GPU access (CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES})..."
python -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}'); print(f'GPU count: {torch.cuda.device_count()}'); print(f'Device name: {torch.cuda.get_device_name(0) if torch.cuda.is_available() else \"N/A\"}')"

# Setup cache
export TORCH_HOME="${SCRATCH}/.cache/torch"
export HF_HOME="${SCRATCH}/.cache/huggingface"
export XDG_CACHE_HOME="${SCRATCH}/.cache"
export PYTHONPATH="${SCRATCH}/third_party/image-matching-models:${PYTHONPATH}"
mkdir -p ${TORCH_HOME} ${HF_HOME}

echo "=========================================="
nvidia-smi 2>/dev/null || echo "No GPU detected"
echo "=========================================="
echo "Running GV-Bench with ${CONFIG}..."
echo "=========================================="

# Run benchmark
CONFIG_NAME=$(basename ${CONFIG} .yaml)
python main.py ${CONFIG} 2>&1 | tee run_${CONFIG_NAME}_${PBS_JOBID%.*}.log

echo "=========================================="
echo "Copying results back..."
echo "=========================================="

# Copy results (with config name prefix to avoid conflicts)
CONFIG_NAME=$(basename ${CONFIG} .yaml)
mkdir -p ${RESULTS_DIR}/results/${CONFIG_NAME}
cp -v *.log ${RESULTS_DIR}/ 2>/dev/null || true
cp -v result*.txt ${RESULTS_DIR}/results/${CONFIG_NAME}/ 2>/dev/null || true
[ -d "results" ] && rsync -a results/ ${RESULTS_DIR}/results/${CONFIG_NAME}/

# Cache models for next run
echo "Caching models..."
mkdir -p ${SOURCE_DIR}/.cache/{torch,huggingface}
mkdir -p ${SOURCE_DIR}/third_party/image-matching-models/matching/model_weights
rsync -a ${TORCH_HOME}/ ${SOURCE_DIR}/.cache/torch/ 2>/dev/null || true
rsync -a ${HF_HOME}/ ${SOURCE_DIR}/.cache/huggingface/ 2>/dev/null || true
rsync -a ${SCRATCH}/third_party/image-matching-models/matching/model_weights/ \
  ${SOURCE_DIR}/third_party/image-matching-models/matching/model_weights/ 2>/dev/null || true

# Cleanup
cd ${RESULTS_DIR}
rm -rf ${SCRATCH}

echo "=========================================="
echo "Completed: $(date)"
echo "=========================================="
