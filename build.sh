#!/bin/bash

# AppKeep 编译脚本
# 确保在项目根目录下运行

# 检查 Wails 是否安装
WAILS_BIN="$HOME/go/bin/wails"
if [ ! -f "$WAILS_BIN" ]; then
    echo "错误: 未找到 Wails 二进制文件 ($WAILS_BIN)。"
    exit 1
fi

echo "--- 开始编译 AppKeep ---"

# 编译应用
$WAILS_BIN build -clean -platform linux/amd64 -tags webkit2_41 $@

if [ $? -eq 0 ]; then
    echo "--- 编译成功 ---"
    echo "可执行文件位于: build/bin/appkeep"
else
    echo "--- 编译失败 ---"
    exit 1
fi
