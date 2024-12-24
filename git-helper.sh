#!/bin/bash

# Set color codes
GREEN='\033[0;32m'
NC='\033[0m' # No Color
YELLOW='\033[1;33m'

clear

echo -e "${GREEN}Git Helper v1.0.1${NC}"
echo
echo "========================================"
echo "           Git Helper Menu"
echo "========================================"
echo
echo " [1] Init and First Push"
echo " [2] Update and Push Changes"
echo
echo "========================================"
read -p "Please select (1/2): " choice

case $choice in
    1)
        echo "===== Disable SSL Verification ====="
        git config --global http.sslVerify false

        echo "===== Initialize Git Repository ====="
        git init

        echo "===== Create README.md ====="
        echo "# luna_kitty_spin_1117_main" > README.md
        git add README.md
        git commit -m "first commit"

        echo "===== Create and Switch to Main Branch ====="
        git branch -M main

        echo "===== Check Remote Repository ====="
        if git remote -v | grep -q origin; then
            echo -e "${YELLOW}[Warning] Remote repository already exists, suggest using option 2${NC}"
            exit 1
        fi

        echo "===== Add Remote Repository ====="
        git remote add origin https://github.com/gameloft333/luna_kitty_spin_1117_main.git
        if [ $? -ne 0 ]; then
            echo "[Failed] Adding remote repository failed"
            exit 1
        fi

        echo "===== Add All Files ====="
        git add .
        if [ $? -ne 0 ]; then
            echo "[Failed] Adding files failed"
            exit 1
        fi

        echo "===== Push to Main Branch ====="
        echo "Pushing... Please wait..."
        git push -u origin main
        if [ $? -ne 0 ]; then
            echo "[Failed] Push failed, retrying..."
            sleep 5
            echo "Second attempt to push..."
            git push -u origin main
            if [ $? -ne 0 ]; then
                echo "[Failed] Push failed again"
                exit 1
            fi
        fi
        ;;

    2)
        echo "===== Disable SSL Verification ====="
        git config --global http.sslVerify false

        echo "===== Fetch Latest Changes ====="
        git fetch origin main
        if [ $? -ne 0 ]; then
            echo "[Failed] Fetching updates failed"
            exit 1
        fi

        echo "===== Merge Remote Changes ====="
        git pull origin main
        if [ $? -ne 0 ]; then
            echo "[Failed] Merging updates failed"
            exit 1
        fi

        echo "===== Show Current Status ====="
        git status

        echo "===== Add All Changes ====="
        git add .
        if [ $? -ne 0 ]; then
            echo "[Failed] Adding files failed"
            exit 1
        fi

        echo "===== Commit Changes ====="
        read -p "Enter commit message (press Enter for default message): " msg
        if [ -z "$msg" ]; then
            git commit -m "Update files"
        else
            git commit -m "$msg"
        fi
        if [ $? -ne 0 ]; then
            echo "[Failed] Commit failed"
            exit 1
        fi

        echo "===== Push Changes ====="
        echo "Pushing... Please wait..."
        git push origin main
        if [ $? -ne 0 ]; then
            echo "[Failed] Push failed, retrying..."
            sleep 5
            echo "Second attempt to push..."
            git push origin main
            if [ $? -ne 0 ]; then
                echo "[Failed] Push failed again"
                exit 1
            fi
        fi
        ;;

    *)
        echo "[Error] Invalid selection"
        exit 1
        ;;
esac

echo "===== Enable SSL Verification ====="
git config --global http.sslVerify true

echo -e "${GREEN}[Success] Operation completed!${NC}" 