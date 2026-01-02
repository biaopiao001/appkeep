#!/bin/bash

echo "=== AppKeep 环境变量继承测试 ==="
echo "测试时间: $(date)"
echo ""

echo "=== 基本信息 ==="
echo "当前用户: $USER"
echo "当前目录: $(pwd)"
echo "Shell: $SHELL"
echo ""

echo "=== PATH 测试 ==="
echo "PATH 长度: ${#PATH} 字符"
echo "PATH 目录数: $(echo $PATH | tr ':' '\n' | wc -l)"
echo ""
echo "PATH 内容:"
echo "$PATH" | tr ':' '\n' | sed 's/^/  /'
echo ""

echo "=== 关键命令测试 ==="
commands=("node" "npm" "python3" "git" "java" "go")
for cmd in "${commands[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "✅ $cmd: $(which $cmd)"
    else
        echo "❌ $cmd: 未找到"
    fi
done
echo ""

echo "=== 开发环境变量 ==="
env_vars=("NODE_ENV" "JAVA_HOME" "GOPATH" "GOROOT" "NVM_DIR" "CUSTOM_VAR")
for var in "${env_vars[@]}"; do
    value="${!var}"
    if [ -n "$value" ]; then
        echo "✅ $var: $value"
    else
        echo "❌ $var: 未设置"
    fi
done
echo ""

echo "=== 环境变量统计 ==="
total_vars=$(env | wc -l)
echo "总环境变量数量: $total_vars"

if [ "$total_vars" -gt 50 ]; then
    echo "✅ 环境变量数量正常，可能已继承主进程环境"
elif [ "$total_vars" -gt 10 ]; then
    echo "⚠️  环境变量数量中等，可能部分继承"
else
    echo "❌ 环境变量数量较少，可能未继承主进程环境"
fi

echo ""
echo "=== 测试完成 ==="