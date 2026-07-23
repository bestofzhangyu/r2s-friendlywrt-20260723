#!/bin/bash
# ============================================================
#  NanoPi R2S — FriendlyWrt + passwall + passwall2 一键编译脚本
#  环境: Ubuntu 20.04/22.04 (物理机 / VM / WSL2)
#  用法: chmod +x build-r2s.sh && ./build-r2s.sh
# ============================================================
set -euo pipefail

# ============ 可配置参数 ============
FRIENDLYWRT_BRANCH="master-v25.12"   # 25.12 最新版; 也可选 master-v22.03 (旧版稳定)
WORKDIR="friendlywrt-rk3328"
PASSWALL_LUCI_REPO="https://github.com/Openwrt-Passwall/openwrt-passwall.git"
PASSWALL_PKG_REPO="https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git"
PASSWALL2_LUCI_REPO="https://github.com/Openwrt-Passwall/openwrt-passwall2.git"
PASSWALL_BRANCH="main"
ENABLE_MENUCONFIG=false               # 设为 true 可在编译前手动配置 (需要终端环境)
# 脚本所在目录 (用于定位 files/ 等自定义文件)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# ====================================

# 颜色输出
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; }
info() { echo -e "${BLUE}[i]${NC} $1"; }
step() { echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BLUE}  $1${NC}"; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# ============================================================
#  Step 0: 环境检查
# ============================================================
check_env() {
    step "步骤 0/7: 环境检查"

    if [ "$(id -u)" -eq 0 ]; then
        err "不能以 root 用户编译 OpenWrt/FriendlyWrt，请切换到普通用户。"
        exit 1
    fi

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        info "操作系统: $PRETTY_NAME"
    fi

    local available_gb
    available_gb=$(df -BG . 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G')
    if [ "${available_gb:-0}" -lt 20 ]; then
        warn "磁盘空间不足: 当前可用 ${available_gb}GB，建议至少 20GB"
        warn "WSL2 用户可通过 'wsl --shutdown' 后扩展虚拟磁盘 (ext4.vhdx) 增加空间"
    else
        log "磁盘空间充足: ${available_gb}GB 可用"
    fi

    local cpu_cores
    cpu_cores=$(nproc 2>/dev/null || echo 1)
    info "CPU 核心数: ${cpu_cores}"

    log "环境检查通过"
}

# ============================================================
#  Step 1: 安装编译依赖
# ============================================================
install_deps() {
    step "步骤 1/7: 安装编译依赖"

    info "更新软件包列表..."
    sudo apt-get update -qq

    info "安装基础编译工具..."
    sudo apt-get install -y -qq \
        build-essential subversion git g++ zlib1g-dev \
        libncurses5-dev gawk gettext unzip file libssl-dev \
        wget libelf-dev ecj fastjar python3 python3-distutils \
        curl rsync cpio xxd bison flex qemu-utils

    info "安装 FriendlyElec 构建环境依赖..."
    wget -q -O /tmp/friendlyarm-build-env.sh \
        https://raw.githubusercontent.com/friendlyarm/build-env-on-ubuntu-bionic/master/install.sh \
        && sudo bash /tmp/friendlyarm-build-env.sh || warn "FriendlyElec 环境脚本下载失败 (可忽略, 基础依赖已安装)"

    log "依赖安装完成"
}

# ============================================================
#  Step 2: 下载 FriendlyWrt RK3328 源码
# ============================================================
download_source() {
    step "步骤 2/7: 下载 FriendlyWrt RK3328 源码"

    if [ -d "$WORKDIR/.repo" ]; then
        warn "工作目录已存在: $WORKDIR/"
        read -r -p "是否更新源码? (y/n) " reply
        if [[ $reply =~ ^[Yy]$ ]]; then
            cd "$WORKDIR"
            info "同步更新..."
            while ! tools/repo sync -c --no-clone-bundle; do
                warn "同步中断, 3 秒后自动重试..."
                sleep 3
            done
            cd ..
            log "源码更新完成"
        fi
        return 0
    fi

    mkdir -p "$WORKDIR"
    cd "$WORKDIR"

    info "下载 repo 工具..."
    git clone https://github.com/friendlyarm/repo --depth 1 tools

    info "初始化 RK3328 仓库 (分支: $FRIENDLYWRT_BRANCH)..."
    tools/repo init -u https://github.com/friendlyarm/friendlywrt_manifests \
        -b "$FRIENDLYWRT_BRANCH" \
        -m rk3328.xml \
        --repo-url=https://github.com/friendlyarm/repo \
        --no-clone-bundle

    info "同步源码 (首次需要下载较多数据, 请耐心等待)..."
    local retry=0
    while ! tools/repo sync -c --no-clone-bundle -j4; do
        retry=$((retry + 1))
        warn "同步中断 (第 $retry 次重试), 5 秒后继续..."
        sleep 5
        if [ $retry -gt 20 ]; then
            err "同步失败超过 20 次, 请检查网络后重新运行脚本"
            exit 1
        fi
    done

    cd ..
    log "源码下载完成"
}

# ============================================================
#  Step 3: 集成 passwall + passwall2
# ============================================================
integrate_passwall() {
    step "步骤 3/7: 集成 passwall + passwall2"

    local fw_dir="$WORKDIR/friendlywrt"
    if [ ! -d "$fw_dir" ]; then
        err "找不到 FriendlyWrt 源码目录: $fw_dir"
        err "请确认 Step 2 源码下载成功"
        exit 1
    fi

    cd "$fw_dir"

    # 直接克隆 passwall 包到 package 目录 (仓库已迁移到 Openwrt-Passwall 组织)
    # 不使用 feeds 方式, 避免与 build.sh 的 feeds install -a 产生重复包
    info "克隆 passwall 源码到 package 目录 (含 passwall + passwall2)..."
    if [ ! -d "package/passwall-packages" ]; then
        git clone --depth 1 -b "$PASSWALL_BRANCH" "$PASSWALL_PKG_REPO" package/passwall-packages
    else
        info "passwall-packages 已存在, 跳过"
    fi
    if [ ! -d "package/passwall-luci" ]; then
        git clone --depth 1 -b "$PASSWALL_BRANCH" "$PASSWALL_LUCI_REPO" package/passwall-luci
    else
        info "passwall-luci 已存在, 跳过"
    fi
    if [ ! -d "package/passwall2-luci" ]; then
        git clone --depth 1 -b "$PASSWALL_BRANCH" "$PASSWALL2_LUCI_REPO" package/passwall2-luci
    else
        info "passwall2-luci 已存在, 跳过"
    fi

    log "passwall + passwall2 集成完成"
    cd ..
}

# ============================================================
#  Step 4: 安装自定义文件 (uci-defaults 脚本等)
# ============================================================
install_custom_files() {
    step "步骤 4/7: 安装自定义文件 (uci-defaults 等)"

    local src_files="$SCRIPT_DIR/files"
    local fw_dir="$WORKDIR/friendlywrt"
    local common_files="$WORKDIR/device/friendlyelec/rk3328/common-files"

    if [ ! -d "$src_files" ]; then
        warn "未找到自定义文件目录: $src_files, 跳过"
        return 0
    fi

    info "自定义文件来源: $src_files"

    # 方式1: 复制到 FriendlyWrt 的 common-files 覆盖目录
    if [ -d "$WORKDIR/device/friendlyelec/rk3328" ]; then
        mkdir -p "$common_files"
        cp -r "$src_files"/* "$common_files"/ 2>/dev/null || true
        log "已复制到 common-files: $common_files"
    else
        warn "device/friendlyelec/rk3328 目录不存在, 尝试备用方式"
    fi

    # 方式2: 复制到 OpenWrt 的 files/ 目录 (OpenWrt 原生覆盖机制)
    if [ -d "$fw_dir" ]; then
        mkdir -p "$fw_dir/files"
        cp -r "$src_files"/* "$fw_dir/files"/ 2>/dev/null || true
        log "已复制到 OpenWrt files/: $fw_dir/files/"
    fi

    # 显示已安装的自定义文件
    info "已安装的自定义文件:"
    find "$src_files" -type f 2>/dev/null | while read -r f; do
        local rel="${f#$src_files/}"
        echo "    /$rel"
    done

    log "自定义文件安装完成"
}

# ============================================================
#  Step 5: 编译 uboot/kernel + 生成 .config
# ============================================================
configure_build() {
    step "步骤 5/7: 编译 uboot/kernel + 生成 .config"

    cd "$WORKDIR"

    # 1. 编译 uboot + kernel, 并生成默认 .config
    #    build.sh rk3328.mk 流程:
    #      source rk3328.mk -> install_toolchain -> build_uboot -> build_kernel
    #      -> build_friendlywrt (feeds update/install + patches + mk-friendlywrt.sh)
    #      -> build_sdimg
    #    DEBUG_DOT_CONFIG=1 让 mk-friendlywrt.sh 在 "make defconfig" 后停止, 不编译 friendlywrt
    #    build_sdimg 会因 rootfs 不存在而失败, 用 || true 忽略
    info "编译 uboot + kernel + 生成默认 .config (DEBUG 模式, 不编译 friendlywrt)..."
    info "这一步会自动完成: feeds update/install, 应用 patches, 生成 .config"
    DEBUG_DOT_CONFIG=1 ./build.sh rk3328.mk || true

    # 2. 检查 .config 是否生成
    if [ ! -f friendlywrt/.config ]; then
        err ".config 未生成, uboot/kernel 构建可能失败"
        err "请检查上面的错误日志"
        exit 1
    fi

    log "uboot + kernel 编译完成, .config 已生成"
    wc -l friendlywrt/.config

    # 3. 追加 passwall + passwall2 配置
    info "追加 passwall + passwall2 配置..."
    cd friendlywrt
    cat >> .config << 'SEED'

# ===== Passwall + Passwall2 =====
CONFIG_PACKAGE_luci-app-passwall=y
CONFIG_PACKAGE_luci-app-passwall2=y

# ===== 常用网络工具 =====
CONFIG_PACKAGE_luci-app-upnp=y
CONFIG_PACKAGE_luci-app-firewall=y
CONFIG_PACKAGE_iptables-nft=y
SEED

    # 4. 让 passwall 配置生效 (处理依赖关系)
    info "生成完整配置 (make defconfig)..."
    make defconfig

    # 5. 验证 passwall 是否被正确启用
    local pw_ok=false pw2_ok=false
    grep -q "CONFIG_PACKAGE_luci-app-passwall=y" .config && pw_ok=true
    grep -q "CONFIG_PACKAGE_luci-app-passwall2=y" .config && pw2_ok=true

    if [ "$pw_ok" = true ]; then
        log "passwall 已启用"
    else
        warn "passwall 未在 .config 中找到, 可能存在依赖问题"
    fi
    if [ "$pw2_ok" = true ]; then
        log "passwall2 已启用"
    else
        warn "passwall2 未在 .config 中找到, 可能存在依赖问题"
    fi

    # 6. 删除官方 feeds 中与 passwall 冲突的包符号链接
    #    build.sh 的 feeds install -a 会安装这些包, 与 passwall-packages 中的版本冲突
    info "删除官方 feeds 中与 passwall 冲突的包..."
    local conflict_pkgs="xray-core v2ray-geodata sing-box chinadns-ng dns2socks hysteria \
        ipt2socks microsocks naiveproxy shadowsocks-libev shadowsocks-rust \
        shadowsocksr-libev simple-obfs tcping trojan-plus tuic-client \
        v2ray-plugin xray-plugin geoview shadow-tls"
    for pkg in $conflict_pkgs; do
        rm -rf "package/feeds/packages/$pkg" 2>/dev/null || true
    done
    rm -rf package/feeds/packages/luci-app-passwall 2>/dev/null || true
    rm -rf package/feeds/packages/luci-app-passwall2 2>/dev/null || true
    rm -rf package/feeds/luci/luci-app-passwall 2>/dev/null || true
    rm -rf package/feeds/luci/luci-app-passwall2 2>/dev/null || true

    # 可选: 手动配置
    if [ "$ENABLE_MENUCONFIG" = true ]; then
        info "启动 menuconfig 手动配置..."
        make menuconfig
    fi

    cd ..
    log "配置完成"
}

# ============================================================
#  Step 6: 编译 friendlywrt + 生成镜像
# ============================================================
build() {
    step "步骤 6/7: 编译 FriendlyWrt + 生成镜像 (首次编译约 1-3 小时)"

    cd "$WORKDIR"

    local jobs
    jobs=$(nproc 2>/dev/null || echo 4)
    info "使用 ${jobs} 线程编译"

    # 编译 FriendlyWrt (直接 make, 不通过 build.sh friendlywrt, 避免重复 feeds install)
    cd friendlywrt

    info "下载编译所需的源码包..."
    make download -j"$jobs" 2>/dev/null || warn "部分下载可能失败, 编译时会自动重试"

    info "编译 FriendlyWrt..."
    make -j"$jobs" || make -j1 V=s

    log "FriendlyWrt 编译完成"

    # 生成 SD 卡镜像
    cd ..
    info "生成 SD 卡镜像..."
    sudo ./build.sh sd-img

    log "SD 卡镜像生成完成"
    cd ..
}

# ============================================================
#  Step 7: 显示结果
# ============================================================
show_result() {
    step "步骤 7/7: 编译结果"

    local out_dir="$WORKDIR/out"

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          编译完成!                        ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "镜像输出目录: ${BLUE}$(pwd)/$out_dir${NC}"
    echo ""

    local found_img=false
    echo "镜像文件:"
    if [ -d "$out_dir" ]; then
        while IFS= read -r f; do
            local size
            size=$(du -h "$f" 2>/dev/null | cut -f1)
            echo "  - $(basename "$f")  ($size)"
            found_img=true
        done < <(find "$out_dir" -name "*.img*" -type f 2>/dev/null | sort)
    fi

    if [ "$found_img" = false ]; then
        warn "未在 $out_dir 找到镜像文件"
        warn "请检查编译日志"
    fi

    echo ""
    echo -e "${YELLOW}刷机方法:${NC}"
    echo "  Linux:   sudo dd if=<镜像文件> bs=1M of=/dev/sdX  (替换 sdX 为实际设备)"
    echo "  Windows: 使用 balenaEtcher / Rufus 烧写到 SD 卡"
    echo ""
    echo -e "${YELLOW}默认访问信息:${NC}"
    echo "  管理页面: http://192.168.2.1  或  http://friendlywrt/"
    echo "  用户名:   root"
    echo "  密码:     (默认无密码, 首次登录请立即设置)"
    echo ""
    echo -e "${YELLOW}已集成功能:${NC}"
    echo "  - PassWall   (服务菜单)"
    echo "  - PassWall2  (服务菜单)"
    echo "  - Android TV 域名映射 (time.android.com → 203.107.6.88)"
    echo "    首次启动自动生效, 解决安卓 TV 连不上网的问题"
    echo ""
}

# ============================================================
#  主流程
# ============================================================
main() {
    echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  NanoPi R2S FriendlyWrt + passwall + passwall2  ║${NC}"
    echo -e "${GREEN}║  分支: ${FRIENDLYWRT_BRANCH}                          ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"

    check_env
    install_deps
    download_source
    integrate_passwall
    install_custom_files
    configure_build
    build
    show_result
}

main "$@"
