#!/bin/bash

# AppKeep 启动脚本
# 确保加载用户的完整 shell 环境

# 加载用户的 .bashrc 以获取完整环境（如 NVM）
if [ -f "$HOME/.bashrc" ]; then
    source "$HOME/.bashrc"
fi

# 加载用户的 .profile
if [ -f "$HOME/.profile" ]; then
    source "$HOME/.profile"
fi

# 启动 AppKeep
exec "$@"