#!/bin/bash

# 设置错误处理
set -e

# 1. 环境与变量准备
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# 确保在 sudo 运行下也能找到用户的 go, wails, npm
USER_PATH=$(sudo -u "$REAL_USER" env "HOME=$USER_HOME" bash -lc 'source "$HOME/.nvm/nvm.sh" >/dev/null 2>&1 || true; printf "%s" "$PATH"')
NPM_BIN_DIR=$(sudo -u "$REAL_USER" env "HOME=$USER_HOME" bash -lc 'source "$HOME/.nvm/nvm.sh" >/dev/null 2>&1 || true; if command -v npm >/dev/null 2>&1; then dirname "$(command -v npm)"; fi')
if [ -z "$NPM_BIN_DIR" ] && [ -d "$USER_HOME/.nvm/versions/node" ]; then
    NPM_BIN_DIR=$(find "$USER_HOME/.nvm/versions/node" -mindepth 2 -maxdepth 2 -type d -name bin -print 2>/dev/null | sort -V | tail -n 1)
fi
export GOPATH=$(sudo -u "$REAL_USER" env "HOME=$USER_HOME" bash -lc 'go env GOPATH 2>/dev/null || printf "%s/go" "$HOME"')
export PATH="$NPM_BIN_DIR:$USER_PATH:/usr/local/go/bin:$GOPATH/bin:$USER_HOME/.local/bin:$PATH"

require_user_cmd() {
    if ! sudo -u "$REAL_USER" env "HOME=$USER_HOME" "PATH=$PATH" "GOPATH=$GOPATH" bash -c 'command -v "$1"' _ "$1" >/dev/null 2>&1; then
        echo "错误: 未找到 $1，请检查 $REAL_USER 用户的构建环境。"
        exit 1
    fi
}

APP_NAME="appkeep"
DISPLAY_NAME="AppKeep"
ICON_SOURCE="build/appicon.png"
INSTALL_DIR="$USER_HOME/.local/bin"
ICON_DIR="$USER_HOME/.local/share/icons"
DESKTOP_DIR="$USER_HOME/.local/share/applications"

echo "🚀 开始安装 $DISPLAY_NAME..."

# 2. 权限清理 (防止之前的 sudo 编译导致 permission denied)
echo "🧹 正在清理文件权限..."
chown -R "$REAL_USER:$REAL_USER" .

# 3. 确保安装目录存在
sudo -u "$REAL_USER" mkdir -p "$INSTALL_DIR"
sudo -u "$REAL_USER" mkdir -p "$ICON_DIR"
sudo -u "$REAL_USER" mkdir -p "$DESKTOP_DIR"

# 4. 编译项目 (必须以原始用户身份运行，以避免 npm/wails 环境冲突)
echo "📂 正在编译应用 (使用 -tags webkit2_41)..."
require_user_cmd wails
require_user_cmd node
require_user_cmd npm
sudo -u "$REAL_USER" env "HOME=$USER_HOME" "PATH=$PATH" "GOPATH=$GOPATH" wails build -tags webkit2_41

# 5. 部署文件
echo "📦 部署二进制文件与图标..."
TMP_BIN=""
cleanup_tmp_bin() {
    if [ -n "$TMP_BIN" ] && [ -e "$TMP_BIN" ]; then
        rm -f "$TMP_BIN"
    fi
}
trap cleanup_tmp_bin EXIT
TMP_BIN="$(mktemp "$INSTALL_DIR/$APP_NAME.tmp.XXXXXX")"
cp "build/bin/$APP_NAME" "$TMP_BIN"
chown "$REAL_USER:$REAL_USER" "$TMP_BIN"
chmod +x "$TMP_BIN"
mv -f "$TMP_BIN" "$INSTALL_DIR/$APP_NAME"
TMP_BIN=""
trap - EXIT

if [ -f "$ICON_SOURCE" ]; then
    cp "$ICON_SOURCE" "$ICON_DIR/$APP_NAME.png"
    chown "$REAL_USER:$REAL_USER" "$ICON_DIR/$APP_NAME.png"
fi

# 6. 创建快捷方式
echo "🖥️ 创建桌面快捷方式..."
cat > "$DESKTOP_DIR/$APP_NAME.desktop" <<EOF
[Desktop Entry]
Name=$DISPLAY_NAME
Comment=Process Monitor and Manager
Exec=$INSTALL_DIR/$APP_NAME
Icon=$ICON_DIR/$APP_NAME.png
Type=Application
Categories=System;Monitor;Utility;
Terminal=false
StartupNotify=true
StartupWMClass=$APP_NAME
EOF
chown "$REAL_USER:$REAL_USER" "$DESKTOP_DIR/$APP_NAME.desktop"

echo "✅ 安装完成！"
echo "您现在可以从菜单启动 '$DISPLAY_NAME'。"
