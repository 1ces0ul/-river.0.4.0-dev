pkgname=river-git
# 这里的版本号是占位符，执行时会被 pkgver() 函数自动更新
pkgver=0.4.0.dev
pkgrel=1
pkgdesc="A dynamic tiling Wayland compositor (Development version 0.4.0)"
arch=('x86_64' 'aarch64')
url="https://codeberg.org/river/river"
license=('GPL-3.0-only')

# 依赖项（根据你提供的 build.zig 和 Zig 0.15 确定）
depends=('wlroots0.19' 'wayland' 'libxkbcommon' 'pixman' 'libevdev' 'libinput')
makedepends=('zig>=0.15.0' 'wayland-protocols' 'scdoc' 'pkgconf' 'git')
provides=('river')
conflicts=('river')

# 指向官方 Git 仓库（如果你想用本地的，可以改成 git+file:///path/to/your/river）
source=("river::git+https://codeberg.org/river/river.git")
sha256sums=('SKIP') # Git 仓库必须 SKIP 校验

pkgver() {
  cd "$srcdir/river"
  # 自动生成类似 0.4.0.dev.r150.g7a2b3c4 的版本号
  git describe --long --tags | sed 's/^v//;s/\([^-]*-g\)/r\1/;s/-/./g'
}

prepare() {
  # 在 src 目录下创建缓存，不进 river 目录，结构更清晰
  # 彻底解决 AccessDenied 的核心：创建属于当前用户的临时缓存目录
  mkdir -p "$srcdir/zig-cache"
  mkdir -p "$srcdir/zig-local-cache"
}

build() {
  # 显式进入源码目录
  cd "$srcdir/river"

  # 解决 Zig 0.15 依赖问题的核心：设置本地缓存目录
  # 强制重定向所有缓存到构建目录，不碰系统的 ~/.cache/zig
  export ZIG_GLOBAL_CACHE_DIR="$srcdir/zig-cache"
  export ZIG_LOCAL_CACHE_DIR="$srcdir/zig-local-cache"

  zig build \
    -Doptimize=ReleaseSafe \
    -Dcpu=baseline \
    -Dpie=true \
    -Dxwayland=true
}

package() {
  # 显式进入源码目录
  cd "$srcdir/river"

  export ZIG_GLOBAL_CACHE_DIR="$srcdir/zig-cache"
  export ZIG_LOCAL_CACHE_DIR="$srcdir/zig-local-cache"

  # 安装到 $pkgdir
  DESTDIR="$pkgdir" zig build \
    -Doptimize=ReleaseSafe \
    -Dcpu=baseline \
    -Dpie=true \
    -Dxwayland=true \
    --prefix /usr \
    install

  # 修正：从 LICENSES 目录安装 GPL-3.0 许可证
  # 根据 river 仓库结构，通常是 LICENSES/GPL-3.0-only.txt 或类似名称
  # 我们直接匹配 LICENSES 目录下的文件
  install -Dm644 LICENSES/* -t "${pkgdir}/usr/share/licenses/${pkgname}/"
}
