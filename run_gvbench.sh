#!/bin/bash

#PBS -N gvbench
#PBS -l ncpus=10
#PBS -l mem=32gb
#PBS -l ngpus=1
#PBS -l walltime=12:00:00

# Job name: gvbench
# Resources: 10 CPUs, 32GB RAM, 1 GPU, 12 hours runtime

# Set up error handling
set -e

# Determine if running under PBS or directly
if [ -z "${PBS_O_WORKDIR}" ]; then
  # Running directly, not through PBS
  SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  SCRATCH="/scratch/nijsmith/manual_run_$$"
  PBS_JOBID="manual_$$"
else
  # Running through PBS
  SOURCE_DIR="${PBS_O_WORKDIR}"
  SCRATCH="/scratch/nijsmith/${PBS_JOBID%.*}"
fi

# Print job information
echo "=========================================="
echo "Job started at: $(date)"
echo "Job ID: ${PBS_JOBID}"
echo "Node: $(hostname)"
echo "Working directory: ${SOURCE_DIR}"
echo "=========================================="

# Create a unique scratch directory
mkdir -p ${SCRATCH}
echo "Scratch directory: ${SCRATCH}"
echo "Source directory: ${SOURCE_DIR}"

# Change to the source directory
cd ${SOURCE_DIR}

# Copy necessary files to scratch
echo "=========================================="
echo "Copying files to scratch..."
echo "=========================================="

# Check and setup image-matching-models before copying
if [ ! -d "${SOURCE_DIR}/third_party/image-matching-models/matching" ]; then
  echo "image-matching-models not properly initialized. Setting up..."
  cd ${SOURCE_DIR}/third_party
  
  # Remove empty directory if it exists
  rm -rf image-matching-models
  
  # Clone the repository directly with submodules
  echo "Cloning image-matching-models repository..."
  git clone --recursive https://github.com/jarvisyjw/image-matching-models.git
  
  cd ${SOURCE_DIR}
  echo "image-matching-models setup complete."
fi

# Check if submodules are initialized
if [ -d "${SOURCE_DIR}/third_party/image-matching-models" ]; then
  # Check if third_party submodules are empty
  SUBMODULE_COUNT=$(find "${SOURCE_DIR}/third_party/image-matching-models/matching/third_party" -mindepth 2 -maxdepth 2 -type f 2>/dev/null | wc -l)
  if [ "$SUBMODULE_COUNT" -eq 0 ]; then
    echo "Submodules appear empty. Initializing..."
    cd "${SOURCE_DIR}/third_party/image-matching-models"
    git submodule update --init --recursive
    cd ${SOURCE_DIR}
    echo "Submodules initialized."
  fi
fi

# Copy code structure (exclude large data/cache directories)
rsync -av --progress \
  --exclude='dataset/images/' \
  --exclude='third_party/image-matching-models/.git/' \
  --exclude='__pycache__/' \
  --exclude='*.pyc' \
  --exclude='.git/' \
  --exclude='results/' \
  --exclude='*.log' \
  ${SOURCE_DIR}/ ${SCRATCH}/

# Copy or link cached model weights if they exist
# Typically stored in ~/.cache/torch or similar locations
if [ -d "${SOURCE_DIR}/.cache" ]; then
  echo "Copying cached models..."
  cp -r ${SOURCE_DIR}/.cache ${SCRATCH}/
fi

# Copy dataset images to scratch if they exist locally
if [ -d "${SOURCE_DIR}/dataset/images" ]; then
  echo "Copying dataset image archives to scratch..."
  mkdir -p ${SCRATCH}/dataset/images
  rsync -av --progress ${SOURCE_DIR}/dataset/images/*.zip ${SCRATCH}/dataset/images/
  
  # Unzip all image archives in scratch (in parallel)
  echo "Unzipping dataset images in scratch (parallel)..."
  cd ${SCRATCH}/dataset/images
  for zipfile in *.zip; do
    if [ -f "$zipfile" ]; then
      echo "Unzipping $zipfile..."
      (unzip -q "$zipfile" && rm "$zipfile") &
    fi
  done
  # Wait for all unzip processes to complete
  wait
  cd ${SCRATCH}
  echo "Dataset images extracted successfully."
else
  echo "WARNING: Dataset images not found at ${SOURCE_DIR}/dataset/images"
  echo "Please download the dataset first from:"
  echo "https://hkustconnect-my.sharepoint.com/:f:/g/personal/jyubt_connect_ust_hk/EkflAPp79spCviRK5EkSGVABrGncg-TfNV5I3ThXxzopLg?e=DdwCAL"
fi

# Change to scratch directory to run the benchmark
cd ${SCRATCH}

# Set up environment
echo "=========================================="
echo "Setting up conda environment..."
echo "=========================================="

# Check if conda is installed, if not install Miniconda
CONDA_INSTALLED=false
if command -v conda &> /dev/null; then
  echo "Conda found: $(which conda)"
  CONDA_INSTALLED=true
else
  echo "Conda not found. Installing Miniconda..."
  
  # Download Miniconda installer
  MINICONDA_INSTALLER="${SCRATCH}/miniconda_installer.sh"
  wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ${MINICONDA_INSTALLER}
  
  # Install Miniconda to scratch (temporary installation)
  CONDA_PREFIX="${SCRATCH}/miniconda3"
  bash ${MINICONDA_INSTALLER} -b -p ${CONDA_PREFIX}
  
  # Clean up installer
  rm ${MINICONDA_INSTALLER}
  
  # Initialize conda for this session (manual activation, not in shell rc)
  eval "$(${CONDA_PREFIX}/bin/conda shell.bash hook)"
  
  # Accept conda Terms of Service
  echo "Accepting conda Terms of Service..."
  conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main
  conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r
  
  echo "Miniconda installed successfully at ${CONDA_PREFIX}"
  CONDA_INSTALLED=true
fi

# Initialize conda if it was already installed
if [ "$CONDA_INSTALLED" = true ] && [ -z "${CONDA_PREFIX}" ]; then
  eval "$(conda shell.bash hook)"
fi

# Create conda environment (no caching - too slow over network disk)
echo "Creating gvbench environment..."
conda create -n gvbench python=3.11 -y
conda activate gvbench

# Install requirements
echo "Installing Python packages..."
pip install -r requirements.txt

# Install image-matching-models dependencies if they exist
if [ -f "third_party/image-matching-models/requirements.txt" ]; then
  echo "Installing image-matching-models dependencies..."
  pip install -r third_party/image-matching-models/requirements.txt
fi

# Initialize submodules if not already done and if in a git repo
if [ -d "third_party/image-matching-models" ]; then
  cd third_party/image-matching-models
  if [ ! -f ".git" ] && [ ! -d ".git" ]; then
    echo "Checking for image-matching-models submodule..."
    # Check if we're in a git repository
    if git rev-parse --git-dir > /dev/null 2>&1; then
      echo "Initializing image-matching-models submodule..."
      cd ${SCRATCH}
      git submodule init
      git submodule update
    else
      echo "Not in a git repository. Skipping submodule initialization."
      echo "Note: Ensure third_party/image-matching-models is properly set up in source directory."
    fi
  fi
  cd ${SCRATCH}
fi

# Set cache directories to use scratch or local cache
export TORCH_HOME="${SCRATCH}/.cache/torch"
export HF_HOME="${SCRATCH}/.cache/huggingface"
export XDG_CACHE_HOME="${SCRATCH}/.cache"
mkdir -p ${TORCH_HOME} ${HF_HOME}

# If cached models exist in source, copy them
if [ -d "${SOURCE_DIR}/.cache/torch" ]; then
  cp -r ${SOURCE_DIR}/.cache/torch/* ${TORCH_HOME}/ 2>/dev/null || true
fi
if [ -d "${SOURCE_DIR}/.cache/huggingface" ]; then
  cp -r ${SOURCE_DIR}/.cache/huggingface/* ${HF_HOME}/ 2>/dev/null || true
fi

# Print GPU information
echo "=========================================="
echo "GPU Information:"
nvidia-smi
echo "=========================================="

# Run the benchmark
echo "=========================================="
echo "Running GV-Bench..."
echo "=========================================="

# Add image-matching-models to Python path
export PYTHONPATH="${SCRATCH}/third_party/image-matching-models:${PYTHONPATH}"
echo "PYTHONPATH: ${PYTHONPATH}"

# Choose which config to run (modify as needed)
CONFIG="config/day.yaml"

# Run with output logging
python main.py ${CONFIG} 2>&1 | tee run_${PBS_JOBID%.*}.log

# Copy results back to working directory
echo "=========================================="
echo "Copying results back..."
echo "=========================================="

# Copy log files
cp -v *.log ${PBS_O_WORKDIR}/ 2>/dev/null || true

# Copy result files (adjust patterns as needed)
if [ -f "result.txt" ]; then
  cp -v result.txt ${PBS_O_WORKDIR}/
fi

# Copy any generated output directories
if [ -d "results" ]; then
  mkdir -p ${PBS_O_WORKDIR}/results
  rsync -av results/ ${PBS_O_WORKDIR}/results/
fi

# Optionally copy cached models back to source for future runs
echo "Copying cached models back to source..."
mkdir -p ${SOURCE_DIR}/.cache/torch
mkdir -p ${SOURCE_DIR}/.cache/huggingface
rsync -av ${TORCH_HOME}/ ${SOURCE_DIR}/.cache/torch/ 2>/dev/null || true
rsync -av ${HF_HOME}/ ${SOURCE_DIR}/.cache/huggingface/ 2>/dev/null || true

# Clean up scratch directory
echo "=========================================="
echo "Cleaning up scratch directory..."
cd ${PBS_O_WORKDIR}
rm -rf ${SCRATCH}
echo "Cleanup complete."

echo "=========================================="
echo "Job completed at: $(date)"
echo "=========================================="
