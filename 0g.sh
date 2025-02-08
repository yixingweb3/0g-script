#!/bin/bash
set -e

# ===============================
# 0g 存储节点管理一键脚本
#
# 功能：
#   1. 安装 0g 存储节点（更新系统、安装依赖、安装 Rust、拉取代码、构建项目、下载配置文件，
#      提示输入 EVM 私钥写入配置文件，创建 systemd 服务并启动）
#   2. 查看服务运行状态
#   3. 卸载存储节点
#   4. 查看 EVM 私钥（miner_key）
#   5. 修改 EVM 私钥（miner_key）
#   6. 查看 0g 存储节点日志
# ===============================

# 安装节点
install_node() {
    echo "=============================================="
    echo "开始安装 0g 存储节点"
    echo "=============================================="

    echo "[1] 更新软件包列表..."
    sudo apt-get update

    echo "[2] 安装必要软件包..."
    sudo apt-get install -y clang cmake build-essential openssl pkg-config libssl-dev git curl jq

    echo "[3] 安装 Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"

    echo "[4] 停止服务并删除旧的 0g-storage-node 目录（如果存在）..."
    sudo systemctl stop zgs 2>/dev/null || true
    rm -rf "$HOME/0g-storage-node"

    echo "[5] 克隆 0g-storage-node 仓库（分支 v0.8.4）..."
    git clone -b v0.8.4 https://github.com/0glabs/0g-storage-node.git "$HOME/0g-storage-node"
    cd "$HOME/0g-storage-node"

    echo "[6] 保存本地修改（如果有）..."
    git stash

    echo "[7] 获取所有标签并检出特定 commit（40d4355）..."
    git fetch --all --tags
    git checkout 40d4355

    echo "[8] 更新子模块..."
    git submodule update --init

    echo "[9] 编译项目，请稍候..."
    cargo build --release

    echo "[10] 下载最新的配置文件..."
    mkdir -p "$HOME/0g-storage-node/run"
    rm -f "$HOME/0g-storage-node/run/config.toml"
    curl -o "$HOME/0g-storage-node/run/config.toml" https://raw.githubusercontent.com/zstake-xyz/test/refs/heads/main/0g_storage_config.toml

    # 校验并交互式提示输入 EVM 私钥（必须以 0x 开头，总长度66位）
    while true; do
        read -p "请输入你的 EVM 私钥 (必须以 0x 开头，总长度66位，例如 0x1234abcd...): " evm_private_key
        if [[ "$evm_private_key" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
            break
        else
            echo "输入格式错误！私钥必须以 0x 开头，总长度为66位，请重新输入。"
        fi
    done
    sed -i -E 's/^[[:space:]]*#?[[:space:]]*miner_key[[:space:]]*=[[:space:]]*"([^"]*)".*/miner_key = "'"${evm_private_key}"'"/' "$HOME/0g-storage-node/run/config.toml"
    echo "配置文件中 miner_key 已更新."

    echo "[11] 创建 systemd 服务文件..."
    sudo tee /etc/systemd/system/zgs.service >/dev/null <<EOF
[Unit]
Description=ZGS Node
After=network.target

[Service]
User=$USER
WorkingDirectory=$HOME/0g-storage-node/run
ExecStart=$HOME/0g-storage-node/target/release/zgs_node --config $HOME/0g-storage-node/run/config.toml
Restart=on-failure
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    echo "[12] 重新加载 systemd，启用并启动服务..."
    sudo systemctl daemon-reload
    sudo systemctl enable zgs
    sudo systemctl start zgs

    echo "=============================================="
    echo "安装完成！"
    echo "你可以选择查看服务状态或查看节点日志。"
    echo "=============================================="
}

# 查看服务状态
status_node() {
    echo "=============================================="
    echo "查看 zgs 服务状态："
    sudo systemctl status zgs
    echo "=============================================="
}

# 卸载节点
uninstall_node() {
    echo "=============================================="
    echo "开始卸载 0g 存储节点..."
    sudo systemctl stop zgs 2>/dev/null || true
    sudo systemctl disable zgs 2>/dev/null || true
    echo "删除 systemd 服务文件..."
    sudo rm -f /etc/systemd/system/zgs.service
    echo "删除 0g-storage-node 目录..."
    rm -rf "$HOME/0g-storage-node"
    echo "重新加载 systemd..."
    sudo systemctl daemon-reload
    echo "卸载完成。"
    echo "=============================================="
}

# 查看当前 EVM 私钥
view_evm_key() {
    echo "=============================================="
    echo "配置文件中 miner_key 配置："
    sed -nE 's/^[[:space:]]*#?[[:space:]]*miner_key[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' "$HOME/0g-storage-node/run/config.toml"
    echo "=============================================="
}

# 修改 EVM 私钥
modify_evm_key() {
    echo "=============================================="
    echo "当前配置文件中 miner_key："
    sed -nE 's/^[[:space:]]*#?[[:space:]]*miner_key[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' "$HOME/0g-storage-node/run/config.toml"
    while true; do
        read -p "请输入新的 EVM 私钥 (必须以 0x 开头，总长度66位，例如 0x1234abcd...): " new_evm_key
        if [[ "$new_evm_key" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
            break
        else
            echo "输入格式错误！私钥必须以 0x 开头，总长度为66位，请重新输入。"
        fi
    done
    sed -i -E 's/^[[:space:]]*#?[[:space:]]*miner_key[[:space:]]*=[[:space:]]*"([^"]*)".*/miner_key = "'"${new_evm_key}"'"/' "$HOME/0g-storage-node/run/config.toml"
    echo "miner_key 已更新。"
    echo "=============================================="
}

# 查看节点日志
view_logs() {
    echo "=============================================="
    echo "显示 0g 存储节点日志最新的 50 行："
    tail -n 50 "$HOME/0g-storage-node/run/log/zgs.log.$(TZ=UTC date +%Y-%m-%d)"
    echo "=============================================="
    echo "完整日志在 /root/0g-storage-node/run/log/zgs.log"
    echo "=============================================="
}

# 检查更新
check_update() {
    # echo "检查是否有新版本..."
    LATEST_VERSION=$(curl -s $REPO_URL || echo "unknown")

    if [[ "$LATEST_VERSION" == "unknown" ]]; then
        echo "无法获取最新版本信息，请检查网络或 GitHub 仓库。"
        return
    fi

    if [[ "$LATEST_VERSION" != "$SCRIPT_VERSION" ]]; then
        echo "发现新版本: $LATEST_VERSION (当前版本: $SCRIPT_VERSION)"
        read -p "是否更新脚本？(Y/n): " update_choice
        update_choice=${update_choice:-Y} # 默认为 Y, 更新
        if [[ "$update_choice" == "y" || "$update_choice" == "Y" ]]; then
            update_script
        fi
        # else
        # echo "当前已是最新版本 ($SCRIPT_VERSION)。"
    fi
}

# ------ 基础模块 ------
# 更新脚本
update_script() {
    echo "正在更新脚本..."
    curl -o "$0" "$SCRIPT_URL" && chmod +x "$0"
    echo "脚本更新成功！请重新运行 '0g' 命令。"
    exit 0
}

# 检查 root 权限
check_root() {
    # 检查是否以 root 权限运行
    if [ "$(id -u)" -ne 0 ]; then
        echo "❌ 需要 root 权限运行此脚本！请使用 'sudo -i' 切换 root 用户再执行。"
        exit 1
    fi
}

# 配置脚本的快捷指令
set_alias() {
    # 获取当前脚本的真实路径
    SCRIPT_PATH=$(realpath "$0")

    # 定义 alias 配置的标记（用于避免重复添加）
    ALIAS_CMD="alias 0g='bash $SCRIPT_PATH'"

    # 检查 ~/.bashrc 是否已经包含 alias 0g
    if ! grep -Fxq "$ALIAS_CMD" ~/.bashrc; then
        echo "$ALIAS_CMD" >>~/.bashrc
        echo "$ALIAS_CMD" >>~/.zshrc

        # 立即在当前 Shell 中生效
        eval "$ALIAS_CMD"

        # 让新终端也生效
        source ~/.bashrc
        source ~/.zshrc

        echo "配置快捷指令成功, 你可以输入 '0g' 来打开脚本管理菜单"
    fi

}

# 配置脚本的快捷指令
set_alias() {
    SCRIPT_PATH=$(realpath "$0")
    ALIAS_CMD="alias 0g='bash $SCRIPT_PATH'"

}

# ------ 变量 ------
SCRIPT_VERSION="1.0.4" # 本地版本
REPO_URL="https://raw.githubusercontent.com/yixingweb3/0g-script/main/version.txt"
SCRIPT_URL="https://raw.githubusercontent.com/yixingweb3/0g-script/main/0g.sh"

# ------ 初始化 ------
check_root
set_alias
check_update # 每次启动时检查更新

# -------------------------------
# 主菜单
# -------------------------------
while true; do
    echo ""
    echo "============================"
    echo "0g 脚本管理菜单"
    echo "============================"
    echo "本脚本由 逸星web3 维护, 免费开源"
    echo "推特: x.com/yixing_web3"
    echo "有问题请在推特留言或加群"
    echo "TG 群: t.me/yixingweb3_group"
    echo "============================"
    echo "1. 安装 0g 存储节点"
    echo "2. 查看服务运行状态"
    echo "3. 卸载存储节点"
    echo "4. 查看 EVM 私钥"
    echo "5. 修改 EVM 私钥"
    echo "6. 查看 0g 存储节点日志"
    echo "7. 检查更新"
    echo "0. 退出"
    echo "✅ 退出后可以输入 '0g' 来打开脚本管理菜单！"
    echo "============================"
    read -p "请选择操作 (0-6): " choice

    case $choice in
    1)
        install_node
        read -p "输入任意键返回主菜单 (Enter): " dummy
        ;;
    2)
        status_node
        read -p "输入任意键返回主菜单 (Enter): " dummy
        ;;
    3)
        uninstall_node
        read -p "输入任意键返回主菜单 (Enter): " dummy
        ;;
    4)
        view_evm_key
        read -p "输入任意键返回主菜单 (Enter): " dummy
        ;;
    5)
        modify_evm_key
        read -p "输入任意键返回主菜单 (Enter): " dummy
        ;;
    6)
        # 选项 6 为持续监控日志，用户需按 Ctrl+C 退出后再返回主菜单
        view_logs
        read -p "输入任意键返回主菜单 (Enter): " dummy
        ;;
    7)
        echo "当前版本 ($SCRIPT_VERSION)。"
        echo "检查是否有新版本..."
        check_update
        ;;
    0)
        echo "退出..."
        exit 0
        ;;
    *)
        echo "无效选项，请重新选择。"
        ;;
    esac
done
