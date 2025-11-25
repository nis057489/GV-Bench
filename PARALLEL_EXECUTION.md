# Parallel Job Execution Guide

## Overview
The benchmark can run different configs in parallel across multiple HPC nodes without conflicts.

## Resource Allocation
- Each job uses **1 GPU, 5 CPUs, 16GB RAM**
- With 2 GPUs per node, you can run **2 jobs per node** simultaneously
- 6 configs = 3 nodes fully utilized (2 jobs each)

## How It Works
- Each job gets a unique scratch directory based on job ID + array index
- Results are organized by config name to prevent overwrites
- Shared cache (models) is read-only, preventing conflicts
- CUDA_VISIBLE_DEVICES ensures GPU isolation between jobs

## Usage

### Submit All Configs in Parallel (Recommended)
```bash
./submit_jobs.sh all
# or
qsub run_gvbench.sh
```
This submits 6 parallel jobs (one per config), each on a separate node.

### Submit Individual Configs
```bash
./submit_jobs.sh day       # Submit only day config
./submit_jobs.sh night     # Submit only night config
./submit_jobs.sh season    # Submit only season config
./submit_jobs.sh weather   # Submit only weather config
./submit_jobs.sh nordland  # Submit only nordland config
./submit_jobs.sh uacampus  # Submit only uacampus config
```

### Manual Testing
Run locally with a specific config:
```bash
./run_gvbench.sh 1  # day
./run_gvbench.sh 2  # night
# etc.
```

## Results Organization
```
results/
├── day/
│   ├── results_*.txt
│   └── ...
├── night/
│   ├── results_*.txt
│   └── ...
├── season/
├── weather/
├── nordland/
└── uacampus/
```

## Monitoring Jobs
```bash
qstat -u $USER           # Check job status
qstat -t 123456[]        # Check specific job array
qdel 123456[]            # Cancel entire job array
qdel 123456[3]           # Cancel specific array element
```

## Config Mapping
- Array Index 1: day.yaml
- Array Index 2: night.yaml
- Array Index 3: season.yaml
- Array Index 4: weather.yaml
- Array Index 5: nordland.yaml
- Array Index 6: uacampus.yaml

## Notes
- Each job uses its own scratch space: `/scratch/nijsmith/${PBS_JOBID}_${ARRAY_INDEX}`
- Model caching is synchronized back to source after each job
- No conflicts between parallel jobs - each has isolated workspace
- First job to complete will cache models, speeding up subsequent jobs
