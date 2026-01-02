#!/bin/bash

echo "=== 环境变量测试 ==="
echo "PATH: $PATH"
echo "PATH 目录数量: $(echo $PATH | tr ':' '\n' | wc -l)"
echo "HOME: $HOME"
echo "USER: $USER"
echo "NODE_ENV: $NODE_ENV"
echo "CUSTOM_VAR: $CUSTOM_VAR"
echo ""

echo "=== PATH 目录详情 ==="
echo "$PATH" | tr ':' '\n' | nl
echo ""

echo "=== 检查常用命令 ==="
echo -n "node: "
if command -v node >/dev/null 2>&1; then
    echo "$(which node) ($(node --version))"
else
    echo "未找到"
fi

echo -n "npm: "
if command -v npm >/dev/null 2>&1; then
    echo "$(which npm) ($(npm --version))"
else
    echo "未找到"
fi

echo -n "python: "
if command -v python >/dev/null 2>&1; then
    echo "$(which python) ($(python --version 2>&1))"
else
    echo "未找到"
fi

echo -n "python3: "
if command -v python3 >/dev/null 2>&1; then
    echo "$(which python3) ($(python3 --version))"
else
    echo "未找到"
fi

echo -n "git: "
if command -v git >/dev/null 2>&1; then
    echo "$(which git) ($(git --version))"
else
    echo "未找到"
fi

echo -n "java: "
if command -v java >/dev/null 2>&1; then
    echo "$(which java) ($(java -version 2>&1 | head -1))"
else
    echo "未找到"
fi

echo ""
echo "=== 环境变量统计 ==="
echo "总环境变量数量: $(env | wc -l)"
echo ""

echo "=== 关键环境变量 ==="
env | grep -E "^(PATH|HOME|USER|SHELL|LANG|NODE|NPM|PYTHON|JAVA)" | sort