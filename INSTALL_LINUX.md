# AppKeep Linux 安装指南

## 安装方式选择

项目提供了两个安装脚本：

### 方式一：完整版安装脚本 (推荐)
```bash
sudo ./install.sh install
```
- 完整的系统兼容性检查
- 详细的错误处理和验证
- 符合 XDG 标准
- 支持多种 Linux 发行版

### 方式二：简化版安装脚本
```bash
sudo ./install_linux.sh
```
- 快速安装，代码简洁
- 基本的错误检查
- 自动检测并推荐使用完整版

## 安装前测试

### 环境检查
运行测试脚本检查安装环境：
```bash
./test_install.sh
```

### 安装预演
运行预演脚本查看安装过程（不实际安装）：
```bash
./dry_run_install.sh
```

## 安装步骤

1. **构建应用程序**
   ```bash
   wails build
   ```

2. **选择安装方式**
   - 推荐使用完整版：`sudo ./install.sh install`
   - 或使用简化版：`sudo ./install_linux.sh`

## 安装内容

安装脚本会将以下内容安装到系统：

- **应用程序**: `/opt/appkeep/appkeep`
- **系统命令**: `/usr/local/bin/appkeep` (符号链接)
- **桌面快捷方式**: `/usr/share/applications/appkeep.desktop`
- **应用图标**: `/usr/share/pixmaps/appkeep.png`
- **卸载脚本**: `/opt/appkeep/uninstall.sh`

## 使用方法

安装完成后，你可以通过以下方式启动应用：

1. **命令行启动**:
   ```bash
   appkeep
   ```

2. **图形界面启动**: 在应用程序菜单中找到 "AppKeep"

## 卸载

### 使用完整版脚本卸载
```bash
sudo ./install.sh uninstall
```

### 使用简化版脚本卸载
```bash
sudo /opt/appkeep/uninstall.sh
```

## 系统要求

- Linux 系统
- Root 权限 (用于安装)
- 已构建的应用程序文件 (`./build/bin/appkeep`)

## 故障排除

### 找不到可执行文件
如果提示找不到 `./build/bin/appkeep`，请先运行：
```bash
wails build
```

### 权限问题
确保以 root 权限运行安装脚本：
```bash
sudo ./install_linux.sh
```

### 图标不显示
如果图标不显示，可能需要重新登录或运行：
```bash
sudo gtk-update-icon-cache /usr/share/pixmaps/
```