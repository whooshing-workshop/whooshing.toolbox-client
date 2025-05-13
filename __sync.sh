#!/bin/bash

# 用法：./copy_excluding_folder.sh 源目录 目标目录 忽略的文件夹名称

SRC="$1"
DEST="$2"
EXCLUDED_DIR_NAME="$3"

if [[ -z "$SRC" || -z "$DEST" || -z "$EXCLUDED_DIR_NAME" ]]; then
    echo "用法: $0 <源目录> <目标目录> <要排除的文件夹名称>"
    exit 1
fi

# 确保目标目录存在
mkdir -p "$DEST"

# 使用 rsync 来递归拷贝，并排除指定名称的文件夹
rsync -av --exclude="$EXCLUDED_DIR_NAME/" "$SRC"/ "$DEST"/
