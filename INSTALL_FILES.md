# AppKeep Linux 安装文件说明

## 创建的安装相关文件

### 安装脚本
1. **install.sh** - 完整版安装脚本（已存在，专业级）
   - 完整的系统兼容性检查
   - 详细的错误处理和验证
   - 支持 install/uninstall 命令
   - 符合 XDG 标准

2. **install_linux.sh** - 简化版安装脚本（新创建）
   - 快速安装，代码简洁
   - 自动检测并推荐使用完整版
   - 包含图标安装和桌面集成

### 测试和验证脚本
3. **test_install.sh** - 安装环境测试脚本
   - 检查必要文件是否存在
   - 验证系统权限
   - 提供安装建议

4. **dry_run_install.sh** - 安装预演脚本
   - 模拟安装过程但不实际修改系统
   - 显示将要执行的操作
   - 预览桌面文件内容

### 文档
5. **INSTALL_LINUX.md** - 详细安装指南
   - 两种安装方式的说明
   - 完整的使用步骤
   - 故障排除指南

### 图标优化工具
7. **optimize_icon.sh** - 图标优化脚本
   - 将图标转换为真正的 PNG 格式
   - 移除白色背景，设置透明度
   - 可选生成多种尺寸的图标

8. **check_transparency.sh** - 透明度检查脚本
   - 验证图标的透明度效果
   - 显示文件格式和大小信息

## 使用流程

### 推荐流程
1. 构建应用：`wails build`
2. 环境检查：`./test_install.sh`
3. 安装预演：`./dry_run_install.sh`
4. 正式安装：`sudo ./install.sh install`

### 快速流程
1. 构建应用：`wails build`
2. 直接安装：`sudo ./install_linux.sh`

## 安装后的文件位置

- **可执行文件**: `/opt/appkeep/appkeep`
- **系统命令**: `/usr/local/bin/appkeep` (符号链接)
- **桌面快捷方式**: `/usr/share/applications/appkeep.desktop`
- **应用图标**: `/usr/share/pixmaps/appkeep.png`
- **卸载脚本**: `/opt/appkeep/uninstall.sh`

## 卸载方法

- 完整版脚本：`sudo ./install.sh uninstall`
- 简化版脚本：`sudo /opt/appkeep/uninstall.sh`

## 文件权限

所有脚本都已设置为可执行权限：
```bash
chmod +x install_linux.sh test_install.sh dry_run_install.sh
```

## 图标优化

原始的 appicon.png 文件实际上是 JPEG 格式，不支持透明度。已经进行了以下优化：

- ✅ 转换为真正的 PNG 格式（RGBA）
- ✅ 移除白色背景，设置为透明
- ✅ 保留原始文件作为备份（appicon_original.png）
- ✅ 支持透明度的现代图标格式

### 图标文件状态
- **appicon.png** - 优化后的透明图标（1024x1024 RGBA）
- **appicon_original.png** - 原始备份文件

### 图标优化工具
- **optimize_icon.sh** - 高级图标优化脚本
- **check_transparency.sh** - 透明度验证脚本

### 验证透明度
运行以下命令检查图标透明度：
```bash
./check_transparency.sh
```