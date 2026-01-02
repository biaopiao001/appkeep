#!/bin/bash

# AppKeep Linux 快速安装脚本
# 作者: jxh <jxh@kingt.top>
# 这是一个简化版本的安装脚本，如需完整功能请使用 install.sh

set -e

APP_NAME="appkeep"
APP_DISPLAY_NAME="AppKeep"
APP_VERSION="1.0.0"
INSTALL_DIR="/opt/$APP_NAME"
BIN_DIR="/usr/local/bin"
DESKTOP_DIR="/usr/share/applications"
ICON_DIR="/usr/share/pixmaps"

# 检查是否存在完整版安装脚本
if [[ -f "./install.sh" ]]; then
    echo "检测到完整版安装脚本 install.sh"
    echo "推荐使用完整版安装脚本，它提供更好的错误处理和系统兼容性检查"
    echo ""
    read -p "是否使用完整版安装脚本? (y/N): " use_full_installer
    if [[ "$use_full_installer" =~ ^[Yy]$ ]]; then
        echo "正在使用完整版安装脚本..."
        exec sudo ./install.sh install
    fi
    echo "继续使用简化版安装脚本..."
    echo ""
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印函数
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否以root权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要root权限运行"
        print_info "请使用: sudo $0"
        exit 1
    fi
}

# 检查必要文件是否存在
check_files() {
    print_info "检查必要文件..."
    
    if [[ ! -f "./build/bin/$APP_NAME" ]]; then
        print_error "找不到可执行文件: ./build/bin/$APP_NAME"
        print_info "请先运行 'wails build' 构建应用程序"
        exit 1
    fi
    
    if [[ ! -f "./appicon.png" ]]; then
        print_warning "找不到图标文件: ./appicon.png"
        print_info "将跳过图标安装"
        INSTALL_ICON=false
    else
        INSTALL_ICON=true
    fi
}

# 创建安装目录
create_directories() {
    print_info "创建安装目录..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$ICON_DIR"
    mkdir -p "$DESKTOP_DIR"
    
    print_success "目录创建完成"
}

# 安装应用程序
install_app() {
    print_info "安装应用程序到 $INSTALL_DIR..."
    
    # 复制启动脚本
    cp "./appkeep-launcher.sh" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/appkeep-launcher.sh"
    
    # 复制可执行文件
    cp "./build/bin/$APP_NAME" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/$APP_NAME"
    
    # 创建符号链接到系统PATH
    ln -sf "$INSTALL_DIR/$APP_NAME" "$BIN_DIR/$APP_NAME"
    
    print_success "应用程序安装完成"
}

# 安装图标
install_icon() {
    if [[ "$INSTALL_ICON" == true ]]; then
        print_info "安装应用图标..."
        cp "./appicon.png" "$ICON_DIR/$APP_NAME.png"
        print_success "图标安装完成"
    fi
}

# 创建桌面文件
create_desktop_entry() {
    print_info "创建桌面快捷方式..."
    
    cat > "$DESKTOP_DIR/$APP_NAME.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$APP_DISPLAY_NAME
Comment=AppKeep - 应用程序管理工具
Exec=$INSTALL_DIR/appkeep-launcher.sh $INSTALL_DIR/$APP_NAME
Icon=$APP_NAME
Terminal=false
Categories=Utility;System;
StartupNotify=true
EOF

    chmod 644 "$DESKTOP_DIR/$APP_NAME.desktop"
    
    print_success "桌面快捷方式创建完成"
}

# 更新桌面数据库
update_desktop_database() {
    print_info "更新桌面数据库..."
    
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
    fi
    
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache "$ICON_DIR" 2>/dev/null || true
    fi
    
    print_success "桌面数据库更新完成"
}

# 创建卸载脚本
create_uninstall_script() {
    print_info "创建卸载脚本..."
    
    cat > "$INSTALL_DIR/uninstall.sh" << 'EOF'
#!/bin/bash

APP_NAME="appkeep"
INSTALL_DIR="/opt/$APP_NAME"
BIN_DIR="/usr/local/bin"
DESKTOP_DIR="/usr/share/applications"
ICON_DIR="/usr/share/pixmaps"

echo "正在卸载 AppKeep..."

# 删除符号链接
rm -f "$BIN_DIR/$APP_NAME"

# 删除桌面文件
rm -f "$DESKTOP_DIR/$APP_NAME.desktop"

# 删除图标
rm -f "$ICON_DIR/$APP_NAME.png"

# 删除安装目录
rm -rf "$INSTALL_DIR"

# 更新桌面数据库
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
fi

echo "AppKeep 已成功卸载"
EOF

    chmod +x "$INSTALL_DIR/uninstall.sh"
    
    print_success "卸载脚本创建完成: $INSTALL_DIR/uninstall.sh"
}

# 显示安装信息
show_install_info() {
    echo
    print_success "=========================================="
    print_success "  AppKeep 安装完成!"
    print_success "=========================================="
    echo
    print_info "安装位置: $INSTALL_DIR"
    print_info "可执行文件: $BIN_DIR/$APP_NAME"
    print_info "桌面快捷方式: $DESKTOP_DIR/$APP_NAME.desktop"
    if [[ "$INSTALL_ICON" == true ]]; then
        print_info "应用图标: $ICON_DIR/$APP_NAME.png"
    fi
    print_info "卸载脚本: $INSTALL_DIR/uninstall.sh"
    echo
    print_info "使用方法:"
    print_info "  命令行: $APP_NAME"
    print_info "  或在应用程序菜单中找到 '$APP_DISPLAY_NAME'"
    echo
    print_info "卸载方法:"
    print_info "  sudo $INSTALL_DIR/uninstall.sh"
    echo
}

# 主函数
main() {
    echo
    print_info "=========================================="
    print_info "  AppKeep Linux 安装程序"
    print_info "=========================================="
    echo
    
    check_root
    check_files
    create_directories
    install_app
    install_icon
    create_desktop_entry
    update_desktop_database
    create_uninstall_script
    show_install_info
}

# 运行主函数
main "$@"