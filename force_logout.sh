#!/bin/bash
# confirm logout of user nijsmith with Y/N
read -p "Are you sure you want to logout user nijsmith? (Y/N): " choice
if [[ "$choice" == "yes_logout" ]]; then
    pkill -KILL -u nijsmith
    echo "User nijsmith has been logged out."
else
    echo "Logout cancelled."
fi