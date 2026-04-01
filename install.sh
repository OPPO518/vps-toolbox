#!/bin/bash

# =========================================================
#  Debian VPS 运维工具箱 - 模块化一键安装脚本
# =========================================================

INSTALL_DIR="/usr/local/x-toolbox"
COMMAND_PATH="/usr/local/bin/x"

echo ">>> 开始安装 VPS 运维工具箱..."

# 1. 安装 git 和基础组件
apt-get update -y && apt-get install -y git curl wget

# 2. 清理旧版本并克隆最新仓库 (请将下面链接换成你的真实仓库地址)
rm -rf "$INSTALL_DIR"
git clone https://github.com/oppo518/vps-toolbox.git "$INSTALL_DIR"

# 3. 赋予主脚本执行权限
chmod +x "$INSTALL_DIR/x.sh"

# 4. 创建全局命令软链接
ln -sf "$INSTALL_DIR/x.sh" "$COMMAND_PATH"

echo ">>> 安装完成！"
echo ">>> 请在终端任意位置输入 x 并回车，即可启动工具箱。"
