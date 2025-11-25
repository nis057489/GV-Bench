#!/bin/bash

# Helper script to run/submit GV-Bench jobs
# Usage: ./submit_jobs.sh [all|day|night|season|weather|nordland|uacampus]

MODE="${1:-all}"

# Check if qsub is available
if command -v qsub &> /dev/null; then
  USE_PBS=true
  echo "PBS detected - will submit jobs to queue"
else
  USE_PBS=false
  echo "No PBS detected - will run directly"
fi

run_config() {
  local index=$1
  local name=$2
  local gpu_id=$3
  
  if [ "$USE_PBS" = true ]; then
    echo "Submitting $name config..."
    qsub -J $index run_gvbench.sh
  else
    echo "Running $name config on GPU $gpu_id..."
    nohup ./run_gvbench.sh $index $gpu_id > "${name}_job.log" 2>&1 &
    echo "  PID: $! (log: ${name}_job.log)"
  fi
}

case "$MODE" in
  all)
    if [ "$USE_PBS" = true ]; then
      echo "Submitting all configs as job array..."
      qsub run_gvbench.sh
    else
      echo "Running all configs in background..."
      # Detect number of GPUs
      NUM_GPUS=$(nvidia-smi -L 2>/dev/null | wc -l || echo "1")
      echo "Detected $NUM_GPUS GPU(s)"
      
      for i in {1..6}; do
        GPU_ID=$(( (i-1) % NUM_GPUS ))
        nohup ./run_gvbench.sh $i $GPU_ID > "job_${i}.log" 2>&1 &
        echo "  Config $i on GPU $GPU_ID (PID: $!, log: job_${i}.log)"
        sleep 1
      done
    fi
    ;;
  day)
    run_config 1 "day" 0
    ;;
  night)
    run_config 2 "night" 1
    ;;
  season)
    run_config 3 "season" 0
    ;;
  weather)
    run_config 4 "weather" 1
    ;;
  nordland)
    run_config 5 "nordland" 0
    ;;
  uacampus)
    run_config 6 "uacampus" 1
    ;;
  *)
    echo "Usage: $0 [all|day|night|season|weather|nordland|uacampus]"
    echo ""
    echo "Examples:"
    echo "  $0 all      - Run/submit all 6 configs"
    echo "  $0 day      - Run/submit only day config"
    echo "  $0 night    - Run/submit only night config"
    echo ""
    if [ "$USE_PBS" = false ]; then
      NUM_GPUS=$(nvidia-smi -L 2>/dev/null | wc -l || echo "1")
      echo "Note: Jobs will run in background (no PBS detected)"
      echo "Detected $NUM_GPUS GPU(s) - jobs will be distributed across GPUs"
      echo "Monitor with: tail -f *_job.log or watch nvidia-smi"
    fi
    exit 1
    ;;
esac

echo "Done!"
