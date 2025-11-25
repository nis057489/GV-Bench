#!/bin/bash

#PBS -N gvbench
#PBS -l ncpus=10
#PBS -l mem=32gb
#PBS -l ngpus=1
#PBS -l walltime=12:00:00

set -e

# Determine if running under PBS or directly
if [ -z "${PBS_O_WORKDIR}" ]; then
  SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  SCRATCH="/scratch/nijsmith/manual_run_$$"
  PBS_JOBID="manual_$$"
  RESULTS_DIR="${SOURCE_DIR}"
else
  SOURCE_DIR="${PBS_O_WORKDIR}"
  SCRATCH="/scratch/nijsmith/${PBS_JOBID%.*}"
  RESULTS_DIR="${PBS_O_WORKDIR}"
fi

echo "=========================================="
echo "Job started: $(date)"
echo "Job ID: ${PBS_JOBID}"
echo "Source: ${SOURCE_DIR}"
echo "Scratch: ${SCRATCH}"
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

# Setup cache
export TORCH_HOME="${SCRATCH}/.cache/torch"
export HF_HOME="${SCRATCH}/.cache/huggingface"
export XDG_CACHE_HOME="${SCRATCH}/.cache"
export PYTHONPATH="${SCRATCH}/third_party/image-matching-models:${PYTHONPATH}"
mkdir -p ${TORCH_HOME} ${HF_HOME}

echo "=========================================="
nvidia-smi 2>/dev/null || echo "No GPU detected"
echo "=========================================="
echo "Running GV-Bench..."
echo "=========================================="

# Run benchmark
CONFIG="config/day.yaml"
python main.py ${CONFIG} 2>&1 | tee run_${PBS_JOBID%.*}.log

echo "=========================================="
echo "Copying results back..."
echo "=========================================="

# Copy results
mkdir -p ${RESULTS_DIR}/results
cp -v *.log ${RESULTS_DIR}/ 2>/dev/null || true
cp -v result*.txt ${RESULTS_DIR}/results/ 2>/dev/null || true
[ -d "results" ] && rsync -a results/ ${RESULTS_DIR}/results/

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
