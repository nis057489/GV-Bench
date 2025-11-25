#!/bin/bash

# Check which GPU each job is using

echo "Active run_gvbench.sh processes and their GPU usage:"
echo "======================================================"

for pid in $(ps aux | grep "[r]un_gvbench.sh" | awk '{print $2}'); do
    # Get the command line
    cmdline=$(ps -p $pid -o args= | head -n1)
    
    # Get CUDA_VISIBLE_DEVICES from environment
    cuda_dev=$(cat /proc/$pid/environ 2>/dev/null | tr '\0' '\n' | grep "^CUDA_VISIBLE_DEVICES=" | cut -d= -f2)
    
    echo "PID $pid: $cmdline"
    echo "  CUDA_VISIBLE_DEVICES: ${cuda_dev:-not set}"
    
    # Find child python processes
    children=$(pgrep -P $pid)
    for child in $children; do
        if ps -p $child -o comm= | grep -q python; then
            child_cuda=$(cat /proc/$child/environ 2>/dev/null | tr '\0' '\n' | grep "^CUDA_VISIBLE_DEVICES=" | cut -d= -f2)
            echo "  └─ Python PID $child - CUDA_VISIBLE_DEVICES: ${child_cuda:-not set}"
        fi
    done
    echo ""
done

echo ""
echo "Current GPU usage per device:"
echo "=============================="
for gpu in 0 1; do
    echo "GPU $gpu:"
    nvidia-smi -i $gpu --query-compute-apps=pid,process_name,used_memory --format=csv,noheader,nounits 2>/dev/null | while read line; do
        echo "  $line"
    done
    [ -z "$(nvidia-smi -i $gpu --query-compute-apps=pid --format=csv,noheader 2>/dev/null)" ] && echo "  (no processes)"
done
