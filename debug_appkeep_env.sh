#!/bin/bash

echo "=== AppKeep 进程环境变量调试 ==="
echo "测试时间: $(date)"
echo ""

echo "=== 进程信息 ==="
echo "当前进程 PID: $$"
echo "父进程 PID: $PPID"
echo ""

echo "=== NVM 相关变量 ==="
env | grep -E "^NVM" | sort || echo "未找到 NVM 变量"
echo ""

echo "=== NODE 相关变量 ==="
env | grep -E "^NODE" | sort || echo "未找到 NODE 变量"
echo ""

echo "=== PATH 分析 ==="
echo "完整 PATH: $PATH"
echo ""
echo "PATH 中的 NVM 路径:"
echo "$PATH" | tr ':' '\n' | grep -i nvm || echo "PATH 中未找到 NVM 路径"
echo ""

echo "=== 环境变量总数 ==="
echo "总计: $(env | wc -l) 个"
echo ""

echo "=== 关键环境变量检查 ==="
important_vars=("HOME" "USER" "SHELL" "PATH" "NVM_DIR" "NVM_BIN" "LANG")
for var in "${important_vars[@]}"; do
    value="${!var}"
    if [ -n "$value" ]; then
        echo "✅ $var: $value"
    else
        echo "❌ $var: 未设置"
    fi
done