# NanoPi R2S FriendlyWrt + passwall + passwall2 编译指南

为 NanoPi R2S (RK3328) 编译集成 passwall、passwall2 及 Android TV 网络修复的 FriendlyWrt 固件。

**已集成功能：**
- PassWall + PassWall2（科学上网/分流）
- Android TV 域名映射（`time.android.com` → `203.107.6.88`，首次启动自动生效，解决安卓原生 TV 连不上网）

---

## 方案概览

| 方案 | 适用场景 | 优点 | 缺点 |
|------|---------|------|------|
| **GitHub Actions 云编译** | 无 Linux 环境 / 想省事 | 免费、不占本地资源 | 编译时间较长、需 GitHub 账号 |
| **WSL2 本地编译** | Windows 用户 | 编译快、可反复调试 | 需开启 WSL2、占磁盘空间 |
| **Linux 主机/VPS** | 有 Linux 机器 | 最稳定、性能好 | 需要有 Linux 环境 |

---

## 方案一：GitHub Actions 云编译（推荐 Windows 用户）

不用装任何本地环境，在 GitHub 上自动编译，完成后下载固件。

### 步骤

1. **注册/登录 GitHub**，新建一个仓库（Public 仓库免费，Private 消费 Actions 额度）

2. **上传项目文件**：将本目录下所有文件上传到仓库：
   ```
   .github/workflows/build-r2s.yml   ← 云编译工作流
   files/etc/uci-defaults/           ← 首次启动脚本 (Android TV 修复)
   build-r2s.sh                      ← 本地编译脚本 (备用)
   ```

3. **触发编译**：
   - 进入仓库 → **Actions** 标签页
   - 左侧选择 **"Build R2S Firmware"**
   - 点击 **"Run workflow"**
   - 可选择分支版本（`master-v25.12` 最新版 或 `master-v22.03` 旧版稳定）

4. **下载固件**：
   - 编译完成后（约 1-3 小时），点击对应的 workflow run
   - 在页面底部 **Artifacts** 区域下载 `r2s-friendlywrt-passwall`
   - 解压后得到 `.img` 固件文件

### 注意事项
- GitHub Actions 单次任务最长 6 小时，首次编译通常在 2-4 小时内完成
- Public 仓库 Actions 时长无限制，Private 仓库每月有 2000 分钟额度
- 如果编译超时，可重试或改用本地编译

---

## 方案二：WSL2 本地编译（Windows 用户）

### 1. 开启 WSL2

> ⚠️ 当前你的系统安全策略可能禁用了 WSL。如需使用，请在 WorkBuddy 安全中心调整「系统级工具」策略。

```powershell
# 在 PowerShell (管理员) 中执行
wsl --install -d Ubuntu-22.04
# 重启电脑后设置 Ubuntu 用户名和密码
```

### 2. 扩展 WSL2 磁盘空间（重要）

FriendlyWrt 编译需要至少 20GB 空间，WSL2 默认可能不够：

```powershell
# 在 PowerShell 中关闭 WSL
wsl --shutdown

# 找到并扩展虚拟磁盘 (路径可能不同)
# Ubuntu 22.04 的磁盘通常在:
# C:\Users\<用户名>\AppData\Local\Packages\CanonicalGroupLimited.Ubuntu22.04*\LocalState\ext4.vhdx
diskpart
> select vdisk file "<上面的路径>"
> compact vdisk
> exit
```

### 3. 在 WSL2 中编译

```bash
# 进入 WSL2 Ubuntu
# 将项目文件复制到 WSL2 中 (可通过 /mnt/c/ 访问 Windows 文件)
cp -r /mnt/c/Users/"Yu Zhang"/WorkBuddy/2026-07-23-20-48-12/R2S-FriendlyWrt ~/r2s-build
cd ~/r2s-build

# 赋予执行权限
chmod +x build-r2s.sh

# 一键编译
./build-r2s.sh
```

脚本会自动完成：环境检查 → 安装依赖 → 下载源码 → 集成 passwall+passwall2 → 安装自定义文件 → 配置 → 编译 → 生成镜像

### 4. 如需手动配置

编辑 `build-r2s.sh`，将 `ENABLE_MENUCONFIG=false` 改为 `true`，编译前会弹出配置菜单，可手动选择需要的包。

---

## 方案三：Linux 主机 / VPS 编译

### 环境要求
- Ubuntu 20.04 或 22.04 (64位)
- 至少 4GB 内存 (推荐 8GB+)
- 至少 25GB 可用磁盘空间
- 非 root 用户

### 编译

```bash
# 克隆或复制项目文件
git clone <你的仓库地址>
cd R2S-FriendlyWrt

chmod +x build-r2s.sh
./build-r2s.sh
```

---

## 刷机方法

### 所需工具
- MicroSD 卡 (建议 8GB 或以上, Class 10)
- 读卡器
- 刷机工具

### Windows 刷机
1. 下载 [balenaEtcher](https://etcher.balena.io/) 或 [Rufus](https://rufus.ie/)
2. 打开软件，选择下载的 `.img` 固件文件
3. 选择 SD 卡设备
4. 点击烧写，等待完成

### Linux 刷机
```bash
# 查看 SD 卡设备名 (插入 SD 卡后)
lsblk
# 假设 SD 卡为 /dev/sdX (请确认, 选错会覆盖其他磁盘!)

# 烧写
sudo dd if=<固件文件.img> bs=1M of=/dev/sdX status=progress
sync
```

### 启动 R2S
1. 将烧写好的 SD 卡插入 R2S
2. 连接网线：**LAN 口** 接电脑，**WAN 口** 接上级路由/光猫
3. 通电启动，等待约 30-60 秒
4. 浏览器访问 `http://192.168.2.1`

---

## 首次配置

### 登录
- 地址：`http://192.168.2.1`
- 用户名：`root`
- 密码：（默认无密码，请立即设置）

### 设置 root 密码
```
系统 → 管理权 → 主机密码 → 设置密码 → 保存并应用
```

### 配置 passwall / passwall2
1. 进入 **服务 → PassWall** 或 **服务 → PassWall2**
2. 点击 **节点订阅 → 添加**
3. 填入你的机场/节点订阅地址
4. 保存并更新订阅
5. 在 **节点列表** 中选择一个节点
6. 在 **基本设置** 中开启主开关
7. 保存并应用

> PassWall 和 PassWall2 可以共存，但建议只启用其中一个的代理主开关，避免冲突。

### Android TV 网络修复（已内置）
固件已内置 uci-defaults 脚本，首次启动时自动添加域名映射：
- `time.android.com` → `203.107.6.88`（阿里云 NTP）
- 此映射解决 Android 原生 TV 首次连不上网的问题（TV 通过该域名验证网络连通性）
- 无需手动操作，开机即生效

---

## 文件说明

| 文件 | 说明 |
|------|------|
| `build-r2s.sh` | 本地一键编译脚本 (Ubuntu/WSL2) |
| `files/etc/uci-defaults/zz-android-tv-fix` | 首次启动脚本 (Android TV 域名映射修复) |
| `.github/workflows/build-r2s.yml` | GitHub Actions 云编译工作流 |
| `r2s-passwall2.seed` | passwall + passwall2 及可选包配置参考 |

---

## 常见问题

### Q: 编译报错 "No space left on device"
A: 磁盘空间不足。WSL2 用户需扩展虚拟磁盘；GitHub Actions 可在 workflow 中增加清理步骤。

### Q: repo sync 一直失败
A: 网络问题。国内用户可尝试设置代理：
```bash
export http_proxy="http://127.0.0.1:7890"
export https_proxy="http://127.0.0.1:7890"
```

### Q: passwall / passwall2 没有出现在 LuCI 菜单中
A: 可能是配置未正确生效。手动检查：
```bash
cd friendlywrt-rk3328/friendlywrt
make menuconfig
# 在 LuCI → Applications 中查找 luci-app-passwall 和 luci-app-passwall2 并勾选
```

### Q: 编译时间太长
A: 首次编译需要编译工具链，耗时较长。后续编译可复用工具链，速度会快很多。建议使用性能较好的机器或增加线程数。

### Q: WAN 和 LAN 口接反了
A: R2S 的网口标注可能与你预期相反。如果无法访问管理页面，尝试对调 WAN/LAN 网线。

### Q: 如何更新 passwall / passwall2 到最新版
A: 重新运行脚本，在源码更新步骤选择 `y`，passwall 包会重新克隆最新版。

---

## 技术细节

### 源码来源
- **FriendlyWrt**: `https://github.com/friendlyarm/friendlywrt_manifests` (分支: master-v25.12)
- **PassWall**: `https://github.com/Openwrt-Passwall/openwrt-passwall` (分支: main)
- **PassWall2**: `https://github.com/Openwrt-Passwall/openwrt-passwall2` (分支: main)
- **PassWall 依赖包**: `https://github.com/Openwrt-Passwall/openwrt-passwall-packages` (分支: main)

### 编译流程
```
repo init + sync (下载源码)
    ↓
集成 passwall + passwall2 (添加 feeds + 直接克隆)
    ↓
安装自定义文件 (uci-defaults: Android TV 域名映射)
    ↓
配置 (追加 passwall+passwall2 到 .config + make defconfig)
    ↓
build.sh friendlywrt (编译内核 + U-Boot + OpenWrt)
    ↓
build.sh sd-img (生成 SD 卡镜像)
    ↓
out/ 目录输出 .img 固件
```

### R2S 规格
- SoC: Rockchip RK3328 (4×Cortex-A53 @ 1.5GHz)
- 内存: 1GB DDR4
- 网口: 2× 千兆以太网 (原生 RTL8211F)
- 支持: FriendlyWrt 25.12 / 22.03, 内核 6.6
