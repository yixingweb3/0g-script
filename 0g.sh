#!/bin/bash
set -e

# ===============================
# 0g 存储节点管理一键脚本
#
# 功能：
#   1. 安装 0g 存储节点（更新系统、安装依赖、安装 Rust、拉取代码、构建项目、下载配置文件，
#      提示输入 EVM 私钥写入配置文件，创建 systemd 服务并启动）
#   2. 查看存储节点运行状态
#   3. 卸载存储节点
#   4. 查看 EVM 私钥（miner_key）
#   5. 修改 EVM 私钥（miner_key）
#   6. 查看 0g 存储节点日志
# ===============================

# ========== 0g 存储节点 =============
# 安装存储节点
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

    # 校验并交互式提示输入 EVM 私钥（必须以 0x 开头，总长度 66 位）
    while true; do
        read -p "请输入你的 EVM 私钥 (推荐新钱包, 必须以 0x 开头，总长度66位，例如 0x1234abcd...): " evm_private_key
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
    echo "查看 zgs 服务状态：(Ctrl + C 退出)"
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

# ========== 0g DA 节点 =============
# 一键安装 DA 节点
install_da_node() {
    echo "=============================================="
    echo "开始安装 0G-DA 节点"
    echo "=============================================="

    echo "[1] 更新软件包列表并安装依赖..."
    sudo apt-get update && sudo apt-get install -y clang cmake build-essential pkg-config libssl-dev protobuf-compiler llvm llvm-dev curl jq

    echo "[2] 安装 Go..."
    cd $HOME
    ver="1.23.3"
    wget -4 -O "go${ver}.linux-amd64.tar.gz" "https://golang.org/dl/go${ver}.linux-amd64.tar.gz"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "go${ver}.linux-amd64.tar.gz"
    rm "go${ver}.linux-amd64.tar.gz"
    echo "export PATH=\$PATH:/usr/local/go/bin:\$HOME/go/bin" >>~/.bash_profile
    source ~/.bash_profile
    go version

    echo "[3] 安装 Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    rustc --version

    echo "[4] 克隆 0G-DA 节点仓库..."
    git clone -b v1.1.3 https://github.com/0glabs/0g-da-node.git "$HOME/0g-da-node"
    cd "$HOME/0g-da-node"

    echo "[5] 保存本地修改（如果有）..."
    git stash

    echo "[6] 获取所有标签并检出特定 commit（9a48827）..."
    git fetch --all --tags
    git checkout 9a48827

    echo "[7] 更新子模块..."
    git submodule update --init

    echo "[8] 编译项目，请稍候..."
    cargo build --release

    echo "[9] 下载参数文件..."
    ./dev_support/download_params.sh

    echo "[10] 生成 BLS 私钥..."
    bls_key=$(cargo run --bin key-gen | tail -n 1)
    echo "生成的 BLS 私钥: $bls_key"

    echo "[11] 下载最新的配置文件..."
    rm -f "$HOME/0g-da-node/config.toml"
    curl -o "$HOME/0g-da-node/config.toml" https://raw.githubusercontent.com/zstake-xyz/test/refs/heads/main/0g_da_config.toml

    echo "[12] 更新配置文件中的 signer_bls_private_key..."
    sed -i -E 's/^[[:space:]]*#?[[:space:]]*signer_bls_private_key[[:space:]]*=[[:space:]]*"([^"]*)".*/signer_bls_private_key = "'"${bls_key}"'"/' "$HOME/0g-da-node/config.toml"

    echo "[13] 提示输入 signer_eth_private_key 和 miner_eth_private_key..."
    read -p "请输入你的 DA 节点签名者私钥 (ETH 私钥，0x 开头，需要至少30个测试网代币): " signer_eth_private_key
    read -p "请输入你的 DA 节点矿工私钥 (ETH 私钥，0x 开头，可以和上面相同): " miner_eth_private_key

    sed -i -E 's/^[[:space:]]*#?[[:space:]]*signer_eth_private_key[[:space:]]*=[[:space:]]*"([^"]*)".*/signer_eth_private_key = "'"${signer_eth_private_key}"'"/' "$HOME/0g-da-node/config.toml"
    sed -i -E 's/^[[:space:]]*#?[[:space:]]*miner_eth_private_key[[:space:]]*=[[:space:]]*"([^"]*)".*/miner_eth_private_key = "'"${miner_eth_private_key}"'"/' "$HOME/0g-da-node/config.toml"

    echo "[14] 创建 DA 节点 systemd 服务文件..."
    sudo tee /etc/systemd/system/0gda.service >/dev/null <<EOF
[Unit]
Description=0G-DA Node
After=network.target

[Service]
User=root
WorkingDirectory=/root/0g-da-node
ExecStart=/root/0g-da-node/target/release/server --config /root/0g-da-node/config.toml
Restart=always
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    echo "[15] 重新加载 systemd，并启用启动 DA 节点服务..."
    sudo systemctl daemon-reload
    sudo systemctl enable 0gda
    sudo systemctl start 0gda

    echo "=============================================="
    echo "0G-DA 节点安装完成！"
    echo "你可以使用相应功能查看服务状态和日志。"
    echo "=============================================="
}

# 查看 DA 节点运行状态
status_da_node() {
    echo "=============================================="
    echo "查看 DA 节点服务状态："
    sudo systemctl status 0gda
    echo "=============================================="
}

# 查看 DA 节点签名者私钥 (signer_eth_private_key)
view_signer_eth_key() {
    echo "=============================================="
    echo "当前 DA 节点签名者私钥 signer_eth_private_key："
    sed -nE 's/^[[:space:]]*#?[[:space:]]*signer_eth_private_key[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' "$HOME/0g-da-node/config.toml"
    echo "=============================================="
}

# 修改 DA 节点签名者私钥 (signer_eth_private_key)
modify_signer_eth_key() {
    echo "当前 DA 节点签名者私钥 signer_eth_private_key："
    sed -nE 's/^[[:space:]]*#?[[:space:]]*signer_eth_private_key[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' "$HOME/0g-da-node/config.toml"
    read -p "请输入新的 signer_eth_private_key: " new_signer_eth_key
    sed -i -E 's/^[[:space:]]*#?[[:space:]]*signer_eth_private_key[[:space:]]*=[[:space:]]*"([^"]*)".*/signer_eth_private_key = "'"${new_signer_eth_key}"'"/' "$HOME/0g-da-node/config.toml"
    echo "signer_eth_private_key 已更新。"
}

# 查看 DA 节点矿工私钥 (miner_eth_private_key)
view_miner_eth_key() {
    echo "=============================================="
    echo "当前 DA 节点矿工私钥 miner_eth_private_key："
    sed -nE 's/^[[:space:]]*#?[[:space:]]*miner_eth_private_key[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' "$HOME/0g-da-node/config.toml"
    echo "=============================================="
}

# 修改 DA 节点矿工私钥 (miner_eth_private_key)
modify_miner_eth_key() {
    echo "当前 DA 节点矿工私钥 miner_eth_private_key："
    sed -nE 's/^[[:space:]]*#?[[:space:]]*miner_eth_private_key[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' "$HOME/0g-da-node/config.toml"
    read -p "请输入新的 miner_eth_private_key: " new_miner_eth_key
    sed -i -E 's/^[[:space:]]*#?[[:space:]]*miner_eth_private_key[[:space:]]*=[[:space:]]*"([^"]*)".*/miner_eth_private_key = "'"${new_miner_eth_key}"'"/' "$HOME/0g-da-node/config.toml"
    echo "miner_eth_private_key 已更新。"
}

# 查看 BLS 私钥 (signer_bls_private_key)
view_bls_key() {
    echo "=============================================="
    echo "当前 DA 节点 BLS 私钥 signer_bls_private_key："
    sed -nE 's/^[[:space:]]*#?[[:space:]]*signer_bls_private_key[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' "$HOME/0g-da-node/config.toml"
    echo "=============================================="
}

# 修改 BLS 私钥 (signer_bls_private_key)
modify_bls_key() {
    echo "当前 DA 节点 BLS 私钥 signer_bls_private_key："
    sed -nE 's/^[[:space:]]*#?[[:space:]]*signer_bls_private_key[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' "$HOME/0g-da-node/config.toml"
    read -p "请输入新的 signer_bls_private_key: " new_bls_key
    sed -i -E 's/^[[:space:]]*#?[[:space:]]*signer_bls_private_key[[:space:]]*=[[:space:]]*"([^"]*)".*/signer_bls_private_key = "'"${new_bls_key}"'"/' "$HOME/0g-da-node/config.toml"
    echo "signer_bls_private_key 已更新。"
}

# 查看 DA 节点日志
view_da_logs() {
    echo "=============================================="
    echo "显示 DA 节点服务日志："
    # 实时日志
    sudo journalctl -u 0gda -f -o cat
    echo "=============================================="
}

# 重启 DA 节点
restart_da_node() {
    echo "正在重启 DA 节点服务..."
    sudo systemctl restart 0gda
    echo "DA 节点服务已重启。"
}

# 卸载 DA 节点
uninstall_da_node() {
    echo "=============================================="
    echo "开始卸载 DA 节点..."
    sudo systemctl stop 0gda 2>/dev/null || true
    sudo systemctl disable 0gda 2>/dev/null || true
    sudo rm -f /etc/systemd/system/0gda.service
    rm -rf "$HOME/0g-da-node"
    sudo systemctl daemon-reload
    echo "DA 节点已卸载。"
    echo "=============================================="
}

# ------ 基础模块 ------
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

# 更新脚本
update_script() {
    echo "正在更新脚本..."
    curl -o "$0" "$SCRIPT_URL" && chmod +x "$0"
    echo "脚本更新成功！请重新运行 '0g' 或 'bash 0g.sh' 命令。"
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

# 定义颜色变量
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
LIGHT_GRAY='\033[0;37m'
UNDERLINE_BLUE='\033[4;34m'
LIGHT_BLUE='\033[1;34m'
NC='\033[0m'

# ------ 变量 ------
SCRIPT_VERSION="1.0.7" # 本地版本
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
    echo -e "${LIGHT_GRAY}============================${NC}"
    echo -e "${CYAN} 0g 脚本管理菜单 (版本 $SCRIPT_VERSION)${NC}"
    echo -e "${LIGHT_GRAY}============================${NC}"
    echo -e "本脚本由 ${YELLOW}逸星web3${NC} 维护, 免费开源"
    echo -e "${MAGENTA}推特:${NC} ${LIGHT_BLUE}x.com/yixing_web3${NC}"
    echo -e "${MAGENTA}TG 群:${NC} ${LIGHT_BLUE}t.me/yixingweb3_group${NC}"
    echo -e "${GREEN}有问题请在推特留言或加群${NC}"
    echo -e "${LIGHT_GRAY}============================${NC}"
    echo -e "${CYAN}1.${NC} 安装 0g 存储节点"
    echo -e "${CYAN}2.${NC} 查看存储节点运行状态"
    echo -e "${CYAN}3.${NC} 卸载存储节点"
    echo -e "${CYAN}4.${NC} 查看 EVM 私钥"
    echo -e "${CYAN}5.${NC} 修改 EVM 私钥"
    echo -e "${CYAN}6.${NC} 查看 0g 存储节点日志"
    echo -e "${CYAN}7.${NC} 检查更新"
    # echo -e "${CYAN}8.${NC} 生成新钱包（助记词、私钥、地址）"
    echo -e "${LIGHT_GRAY}============================${NC}"
    echo -e "${CYAN}8.${NC} 安装 DA 节点"
    echo -e "${CYAN}9.${NC} 查看 DA 节点运行状态"
    echo -e "${CYAN}10.${NC} 查看 DA 节点签名者私钥"
    echo -e "${CYAN}11.${NC} 修改 DA 节点签名者私钥"
    echo -e "${CYAN}12.${NC} 查看 DA 节点矿工私钥"
    echo -e "${CYAN}13.${NC} 修改 DA 节点矿工私钥"
    echo -e "${CYAN}14.${NC} 查看 BLS 私钥"
    echo -e "${CYAN}15.${NC} 修改 BLS 私钥"
    echo -e "${CYAN}16.${NC} 查看 DA 节点日志"
    echo -e "${CYAN}17.${NC} 重启 DA 节点"
    echo -e "${CYAN}18.${NC} 卸载 DA 节点"
    echo -e "${LIGHT_GRAY}============================${NC}"
    echo -e "${CYAN}0.${NC} 退出"
    echo -e "${LIGHT_GRAY}============================${NC}"
    echo -e "退出后可以输入 ${YELLOW}0g${NC} 来打开脚本管理菜单！"
    echo -e "${LIGHT_GRAY}============================${NC}"
    read -p "$(echo -e "${YELLOW}请选择操作 (0-18): ${NC}")" choice

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
        view_logs
        read -p "输入任意键返回主菜单 (Enter): " dummy
        ;;
    7)
        echo "当前版本 ($SCRIPT_VERSION)。"
        echo "检查是否有新版本..."
        check_update
        ;;
        # 8)
        #     generate_wallet_module
        #     read -p "输入任意键返回主菜单 (Enter): " dummy
        #     ;;
    8)
        install_da_node
        read -p "输入任意键返回主菜单 (Enter): " dummy
        ;;
    9)
        status_da_node
        read -p "输入任意键返回主菜单 (Enter): " dummy
        ;;
    10)
        view_signer_eth_key
        read -p "输入任意键返回主菜单 (Enter): " dummy
        ;;
    11)
        modify_signer_eth_key
        read -p "输入任意键返回主菜单 (Enter): " dummy
        ;;
    12)
        view_miner_eth_key
        read -p "输入任意键返回主菜单 (Enter): " dummy
        ;;
    13)
        modify_miner_eth_key
        read -p "输入任意键返回主菜单 (Enter): " dummy
        ;;
    14)
        view_bls_key
        read -p "输入任意键返回主菜单 (Enter): " dummy
        ;;
    15)
        modify_bls_key
        read -p "输入任意键返回主菜单 (Enter): " dummy
        ;;
    16)
        view_da_logs
        read -p "输入任意键返回主菜单 (Enter): " dummy
        ;;
    17)
        restart_da_node
        read -p "输入任意键返回主菜单 (Enter): " dummy
        ;;
    18)
        uninstall_da_node
        read -p "输入任意键返回主菜单 (Enter): " dummy
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
