# Arch Linux PKGBUILD 编写教程

本教程通过分析 Arch Linux 官方仓库中的 `river` 包，详细讲解 PKGBUILD 的每一项及其作用。

---

## 目录

1. [PKGBUILD 概述](#pkgbuild-概述)
2. [基础元信息](#基础元信息)
3. [依赖项详解](#依赖项详解)
4. [源代码管理](#源代码管理)
5. [校验与安全](#校验与安全)
6. [prepare() - 准备阶段](#prepare---准备阶段)
7. [build() - 构建阶段](#build---构建阶段)
8. [check() - 测试阶段](#check---测试阶段)
9. [package() - 打包阶段](#package---打包阶段)
10. [常见问题解答](#常见问题解答)

---

## PKGBUILD 概述

PKGBUILD 是 Arch Linux 的包构建脚本，定义了如何从源码编译并打包成 `.pkg.tar.zst` 安装包。

PKGBUILD 的设计原则：
- **可重现性**：任何人在任何时间构建，结果一致
- **完整性**：所有源文件必须被声明和校验
- **可控性**：构建过程不依赖隐式行为或外部状态

---

## 基础元信息

```bash
pkgname=river
pkgver=0.4.2
pkgrel=1
pkgdesc='a non-monotonic Wayland compositor'
arch=('x86_64')
url="https://isaacfreund.com/software/river/"
license=('0BSD' 'CC-BY-SA-4.0' 'GPL-3.0-only' 'MIT')
```

| 字段 | 说明 | 注意事项 |
|------|------|----------|
| `pkgname` | 包名，必须唯一 | 只能包含字母、数字、@、.、_、+、- |
| `pkgver` | 版本号，必须与上游一致 | 不能包含 `-`，用 `_` 替代 |
| `pkgrel` | 包发布号 | 每次 PKGBUILD 更新递增，用于同一版本的多次修订 |
| `pkgdesc` | 包描述 | 会显示在 `pacman -Ss` 搜索结果中 |
| `arch` | 支持的架构 | `'x86_64'`, `'aarch64'`, `'any'`，留空表示所有架构 |
| `url` | 项目主页 | 帮助用户了解项目 |
| `license` | 许可证类型 | 使用 SPDX 标准标识符 |

---

## 依赖项详解

```bash
depends=(
    'glibc'
    'libevdev'
    'libinput'
    'libxkbcommon'
    'pixman'
    'wayland'
    'wlroots0.20'
    'xorg-xwayland'
)

makedepends=(
    'git'
    'scdoc'
    'wayland-protocols'
    'zig'
)
```

### 依赖类型

| 类型 | 含义 | 安装时机 |
|------|------|----------|
| `depends` | 运行时依赖 | `pacman -S` 安装包时自动安装 |
| `makedepends` | 构建时依赖 | `makepkg` 时自动安装（需开启 `-s`） |
| `checkdepends` | 测试时依赖 | `makepkg --check` 时使用 |
| `optdepends` | 可选依赖 | 提示用户但不强制安装 |

### 依赖版本锁定

```bash
'wlroots0.20'        # 精确版本：wlroots 0.20.x
'zig>=0.15.0'        # 最低版本：zig 0.15.0 或更高
'python<3.12'        # 版本上限：python 低于 3.12
```

### 为什么需要 `wlroots0.20` 而不是 `wlroots`？

river 0.4.2 适配的是 wlroots 0.20.x API。如果上游更新了 wlroots 0.21，可能导致 API 不兼容或构建失败。锁定版本确保构建环境的稳定。

### 为什么 `glibc` 要显式列出？

在 Arch Linux 中，`glibc` 属于 `base` 组，是系统隐式依赖。但显式列出可以：
- 让 `namcap` 正确分析依赖关系
- 明确声明对系统底层库的要求
- 在容器/隔离环境中构建时确保依赖完整

---

## 源代码管理

```bash
source=(git+https://codeberg.org/river/river.git#tag=v${pkgver}?signed)

source+=(zig-pixman-0.3.0.tar.gz::https://codeberg.org/ifreund/zig-pixman/archive/v0.3.0.tar.gz
         zig-wayland-0.5.0.tar.gz::https://codeberg.org/ifreund/zig-wayland/archive/v0.5.0.tar.gz
         zig-wlroots-0.20.0.tar.gz::https://codeberg.org/ifreund/zig-wlroots/archive/v0.20.0.tar.gz
         zig-xkbcommon-0.4.0.tar.gz::https://codeberg.org/ifreund/zig-xkbcommon/archive/v0.4.0.tar.gz)

noextract=("${source[@]:1}")
```

### 源码声明语法

```bash
# 基础格式
source=('filename::url')

# 分隔符说明
filename::url      # 下载为 filename
url               # 使用 URL 末尾的文件名
::url             # 下载到当前目录（无文件名）
```

### Git 源的特殊语法

```bash
git+url#tag=v1.0.0           # 克隆并 checkout 到 tag
git+url#commit=abc123        # 克隆并 checkout 到指定 commit
git+url#branch=develop       # 克隆并 checkout 到分支
git+url#tag=v1.0.0?signed    # 验证 GPG 签名
```

- `#tag=v${pkgver}` 使用变量插值，动态指定版本
- `?signed` 表示验证 tag 的 GPG 签名

### 追加源码

```bash
source=(...)        # 初始数组
source+=(...)       # 向数组追加内容，等价于 source+=(...)
```

### noextract 的作用

```bash
noextract=("${source[@]:1}")
```

- 告诉 makepkg **不要解压**这些文件
- 这里的 `"${source[@]:1}"` 是 bash 切片语法，取数组从索引 1 开始的所有元素（即排除第一个 git 源）
- 用于 Zig 项目：因为 `zig fetch` 直接读取 tar.gz 文件，不需要解压

### 为什么 Zig 依赖要手动声明？

#### Zig 项目的依赖结构

```
river 源码
├── build.zig          # 构建脚本
├── build.zon          # 依赖声明
└── ...

build.zon 内容示例：
.{
    .dependencies = .{
        .zig_wlroots = .{
            .url = "https://...",
            .hash = "...",
        },
    },
}
```

#### 不声明 vs 声明

**不声明（依赖 Zig 自动处理）：**
```bash
# 构建时
zig build
  → 读取 build.zon
  → 发现需要 zig-pixman
  → 询问 registry 或自动获取最新兼容版本
  → 下载到 ~/.cache/zig
```

问题：
- 上游更新了 `zig-pixman 0.3.1` → 构建使用新版本
- 下个月构建可能拿到 `0.3.2` → 与今天的结果不一致
- 无法离线构建

**声明（PKGBUILD 管理）：**
```bash
# 构建前
makepkg -s
  → 下载 zig-pixman-0.3.0.tar.gz
  → 校验 sha256sums
  → 存储到 src/
  → zig fetch 读取本地文件

# 构建时
zig build
  → 使用确定版本的源码
```

好处：
- 版本固定：永远是 `0.3.0`
- 校验：SHA256 确保文件完整
- 可重现：任何人任何时间构建，结果一致

---

## 校验与安全

```bash
validpgpkeys=('5FBDF84DD2278DB2B8AD8A5286DED400DDFD7A11')

sha256sums=('def9524ece826e17760264a6196836997e2624f70dd2daafc9f5a30ba8e713e8'
            'cd7fe3415d4d58685a94fdedd308e9994a37f012828940cfb603461de7f2c6ad'
            'fa9705e83613b5555d7117ce5c602f10591d6598e69a73fba2e6039200db4f4b'
            '75af3510386c639582693d01788579abde4dca9ce1ae6703c1e877ec8123d106'
            'e6df77d511cf9402f6ac08455c8d1fb727b6c3d66191e246671f62e5db083c49')
```

### GPG 签名验证

```bash
validpgpkeys=('5FBDF84DD2278DB2B8AD8A5286DED400DDFD7A11')
#                                    ↑ 维护者 Isaac Freund 的 GPG 指纹
```

- 用于验证 git tag 的 GPG 签名
- 白名单机制：只有列出的指纹才被信任
- `#tag=v${pkgver}?signed` 启用签名验证

### 文件校验

```bash
sha256sums=('...'
            'SKIP'    # 跳过校验，用于 git 源
            '...')
```

校验方式（按安全性递增）：
- `SKIP` - 不校验
- `SKIP`（git 源必须）- git 源通过 commit hash 验证
- `sha256sums` - SHA-256 校验和
- `b2sums` - BLAKE2 校验（Arch 默认推荐）

---

## prepare() - 准备阶段

```bash
prepare() {
    zig fetch --global-cache-dir ./zig-global-cache "./${source[1]%%::*}"
    zig fetch --global-cache-dir ./zig-global-cache "./${source[2]%%::*}"
    zig fetch --global-cache-dir ./zig-global-cache "./${source[3]%%::*}"
    zig fetch --global-cache-dir ./zig-global-cache "./${source[4]%%::*}"
}
```

### 作用

`prepare()` 在源码解压后、编译前执行，用于：
- 打补丁
- 生成构建文件
- 下载/注册依赖（这里是 Zig 的场景）

### `zig fetch` 详解

```bash
zig fetch --global-cache-dir ./zig-global-cache "./${source[1]%%::*}"
```

- `zig fetch` - 下载并注册 Zig 依赖
- `--global-cache-dir ./zig-global-cache` - 指定缓存目录
- `"./${source[1]%%::*}"` - bash 参数展开：
  - `${source[1]}` = `zig-pixman-0.3.0.tar.gz::https://...`
  - `%%::*` = 去掉 `::` 及后面的内容
  - 结果 = `./zig-pixman-0.3.0.tar.gz`

### 为什么不直接解压 tar.gz？

```bash
noextract=("${source[@]:1}")  # 告诉 makepkg 不要解压
```

`zig fetch` 可以直接读取 tar.gz 文件，不需要先解压。这避免了：
- 解压后的文件占用空间
- 多余的 I/O 操作

---

## build() - 构建阶段

```bash
build() {
  cd $pkgname
  DESTDIR="build" zig build \
    --summary all \
    --prefix /usr \
    --search-prefix /usr \
    --global-cache-dir ../zig-global-cache \
    --system ../zig-global-cache/p \
    --build-id=sha1 \
    -Dtarget=native-linux.6.6-gnu.2.40 \
    -Dcpu=baseline \
    -Dpie \
    -Doptimize=ReleaseSafe \
    -Dxwayland
}
```

### 核心选项解析

| 选项 | 作用 | 不写会怎样 |
|------|------|----------|
| `DESTDIR="build"` | 临时安装目录 | 安装到系统路径（需要 root） |
| `--prefix /usr` | 安装路径前缀 | 默认可能是 `/usr/local` |
| `--search-prefix /usr` | 系统库搜索路径 | 找不到系统依赖的库/头文件 |
| `--global-cache-dir` | Zig 依赖缓存 | 用 `~/.cache/zig`（不可控） |
| `--system` | Zig 标准库位置 | 依赖系统路径 |
| `--build-id=sha1` | 标记二进制构建 ID | 调试/strip 时缺少信息 |

### -D 系列选项（Zig 特性）

```bash
-Dtarget=native-linux.6.6-gnu.2.40
```

- 指定目标平台
- `native` = 检测当前机器
- `linux.6.6` = 内核版本
- `gnu.2.40` = glibc 版本

**为什么要指定 glibc 版本？**
- glibc 2.40 是 Arch Linux 当前使用的版本
- 生成的二进制与系统 glibc 兼容
- 不指定可能导致链接错误或运行时问题

```bash
-Dcpu=baseline
```

- 生成通用 CPU 代码
- 兼容所有 x86_64 CPU
- 性能略低于针对特定 CPU 优化

```bash
-Dpie
```

- Position Independent Executable
- 增强 ASLR（地址空间布局随机化）安全性
- 现代 Linux 默认要求

```bash
-Doptimize=ReleaseSafe
```

优化级别：
- `Debug` - 无优化，便于调试
- `ReleaseSafe` - 优化但保留安全检查
- `ReleaseFast` - 最大优化
- `ReleaseSmall` - 优化体积

```bash
-Dxwayland
```

- 启用 XWayland 支持
- 允许运行 X11 应用
- 需要 `xorg-xwayland` 运行时依赖

---

## check() - 测试阶段

```bash
check() {
  cd $pkgname
  zig build test \
    --summary all \
    --prefix /usr \
    --search-prefix /usr \
    --global-cache-dir ../zig-global-cache \
    --system ../zig-global-cache/p \
    --build-id=sha1 \
    -Dtarget=native-linux.6.6-gnu.2.40 \
    -Dcpu=baseline \
    -Dpie \
    -Doptimize=ReleaseSafe \
    -Dxwayland
}
```

- 运行项目的测试套件
- 确保构建正确
- 可用 `makepkg --nocheck` 跳过

---

## package() - 打包阶段

```bash
package() {
  cd $pkgname

  cp -a build/* "$pkgdir"

  install -Dm644 README.md -t "$pkgdir/usr/share/doc/$pkgname"
  install -Dm644 contrib/river.desktop -t "$pkgdir/usr/share/wayland-sessions"

  install -m644 -Dt "${pkgdir}/usr/share/licenses/${pkgname}" LICENSES/{0BSD.txt,MIT.txt}
}
```

### $pkgdir 是什么？

`$pkgdir` 是 pacman 的目标根目录，通常是 `/pkg/<pkgname>`。包的内容最终会安装到系统的 `/` 根目录下。

```bash
$pkgdir/usr/bin/river    →    /usr/bin/river
$pkgdir/usr/share/...   →    /usr/share/...
```

### install 命令

```bash
install -Dm644 README.md -t "$pkgdir/usr/share/doc/$pkgname"
```

- `-D` - 创建父目录
- `-m644` - 权限 644（所有者读写，其他人读）
- `-t directory` - 目标目录

等价于：
```bash
mkdir -p "$pkgdir/usr/share/doc/$pkgname"
cp README.md "$pkgdir/usr/share/doc/$pkgname/"
chmod 644 "$pkgdir/usr/share/doc/$pkgname/README.md"
```

### Brace Expansion（花括号展开）

```bash
LICENSES/{0BSD.txt,MIT.txt}
```

等于：
```bash
LICENSES/0BSD.txt LICENSES/MIT.txt
```

### 目录结构规范

| 目录 | 用途 |
|------|------|
| `/usr/bin/` | 可执行文件 |
| `/usr/lib/` | 库文件 |
| `/usr/share/doc/<pkgname>/` | 文档 |
| `/usr/share/wayland-sessions/` | Wayland 会话桌面文件 |
| `/usr/share/licenses/<pkgname>/` | 许可证文件 |

---

## 常见问题解答

### Q: glibc 是干什么的？

**A:** `glibc`（GNU C Library）是 Linux 系统最底层的 C 标准库，提供 `printf`、`malloc`、`pthread`、文件操作、网络编程等基础函数。所有程序都依赖它。

在 Arch Linux 中属于 `base` 组，隐式依赖，不需要显式列出。但显式列出可以让依赖关系更清晰。

### Q: 为什么源文件要声明和校验？

**A:** PKGBUILD 的设计原则是"所有源文件必须被声明和校验"，保证构建的可重现性：

1. **版本锁定**：不依赖"最新版本"，每次构建使用相同的源码版本
2. **完整性校验**：SHA256 确保文件没被篡改
3. **可重现**：任何人任何时间构建，结果一致
4. **可离线**：依赖已下载，不依赖网络

### Q: zig fetch 和 zig build --global-cache-dir 有什么区别？

**A:** 
- `zig fetch` - 下载并注册第三方库的依赖信息
- `--global-cache-dir` - 设置缓存目录位置，避免污染 `~/.cache/zig`

两者配合使用：
```bash
prepare() {
    zig fetch --global-cache-dir ./zig-global-cache ...
}
build() {
    zig build --global-cache-dir ../zig-global-cache ...
}
```

### Q: -Dtarget 和 -Dcpu 有什么区别？

**A:**
- `-Dtarget` - 整个构建目标平台（操作系统 + CPU 架构 + C 库版本）
- `-Dcpu` - CPU 特定优化

```bash
-Dtarget=native-linux.6.6-gnu.2.40    # 平台：Linux + glibc 2.40
-Dcpu=baseline                          # CPU：通用代码
```

### Q: 什么时候需要 provides 和 conflicts？

```bash
provides=('river')          # 声明提供这个虚拟包
conflicts=('river-classic') # 声明与这个包冲突
```

- 用于包名不同但功能相同的场景
- `river-git` 提供了 `river`，所以与官方 `river` 冲突
- 用户安装 `river-git` 后，系统认为已安装 `river`

---

## 附录：完整示例对照

### 官方 PKGBUILD（完整）

```bash
pkgname=river
pkgver=0.4.2
pkgrel=1
pkgdesc='a non-monotonic Wayland compositor'
arch=('x86_64')
url="https://isaacfreund.com/software/river/"
license=('0BSD' 'CC-BY-SA-4.0' 'GPL-3.0-only' 'MIT')
depends=(
    'glibc'
    'libevdev'
    'libinput'
    'libxkbcommon'
    'pixman'
    'wayland'
    'wlroots0.20'
    'xorg-xwayland'
)
makedepends=(
    'git'
    'scdoc'
    'wayland-protocols'
    'zig'
)
source=(git+https://codeberg.org/river/river.git#tag=v${pkgver}?signed)
source+=(zig-pixman-0.3.0.tar.gz::https://codeberg.org/ifreund/zig-pixman/archive/v0.3.0.tar.gz
         zig-wayland-0.5.0.tar.gz::https://codeberg.org/ifreund/zig-wayland/archive/v0.5.0.tar.gz
         zig-wlroots-0.20.0.tar.gz::https://codeberg.org/ifreund/zig-wlroots/archive/v0.20.0.tar.gz
         zig-xkbcommon-0.4.0.tar.gz::https://codeberg.org/ifreund/zig-xkbcommon/archive/v0.4.0.tar.gz)
noextract=("${source[@]:1}")
conflicts=('river-classic')
validpgpkeys=('5FBDF84DD2278DB2B8AD8A5286DED400DDFD7A11')
sha256sums=('def9524ece826e17760264a6196836997e2624f70dd2daafc9f5a30ba8e713e8'
            'cd7fe3415d4d58685a94fdedd308e9994a37f012828940cfb603461de7f2c6ad'
            'fa9705e83613b5555d7117ce5c602f10591d6598e69a73fba2e6039200db4f4b'
            '75af3510386c639582693d01788579abde4dca9ce1ae6703c1e877ec8123d106'
            'e6df77d511cf9402f6ac08455c8d1fb727b6c3d66191e246671f62e5db083c49')

prepare() {
    zig fetch --global-cache-dir ./zig-global-cache "./${source[1]%%::*}"
    zig fetch --global-cache-dir ./zig-global-cache "./${source[2]%%::*}"
    zig fetch --global-cache-dir ./zig-global-cache "./${source[3]%%::*}"
    zig fetch --global-cache-dir ./zig-global-cache "./${source[4]%%::*}"
}

build() {
  cd $pkgname
  DESTDIR="build" zig build \
    --summary all \
    --prefix /usr \
    --search-prefix /usr \
    --global-cache-dir ../zig-global-cache \
    --system ../zig-global-cache/p \
    --build-id=sha1 \
    -Dtarget=native-linux.6.6-gnu.2.40 \
    -Dcpu=baseline \
    -Dpie \
    -Doptimize=ReleaseSafe \
    -Dxwayland
}

check() {
  cd $pkgname
  zig build test \
    --summary all \
    --prefix /usr \
    --search-prefix /usr \
    --global-cache-dir ../zig-global-cache \
    --system ../zig-global-cache/p \
    --build-id=sha1 \
    -Dtarget=native-linux.6.6-gnu.2.40 \
    -Dcpu=baseline \
    -Dpie \
    -Doptimize=ReleaseSafe \
    -Dxwayland
}

package() {
  cd $pkgname
  cp -a build/* "$pkgdir"
  install -Dm644 README.md -t "$pkgdir/usr/share/doc/$pkgname"
  install -Dm644 contrib/river.desktop -t "$pkgdir/usr/share/wayland-sessions"
  install -m644 -Dt "${pkgdir}/usr/share/licenses/${pkgname}" LICENSES/{0BSD.txt,MIT.txt}
}
```

---

## 参考资料

- [Arch Wiki: PKGBUILD](https://wiki.archlinux.org/title/PKGBUILD)
- [Arch Wiki: Makepkg](https://wiki.archlinux.org/title/Makepkg)
- [river 官方打包说明](https://codeberg.org/river/river/src/branch/master/PACKAGING.md)
