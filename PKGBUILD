# Maintainer: Your Name <youremail@example.com>
pkgname=rijan-git
pkgver=fd08913
pkgrel=1
pkgdesc="An experimental Wayland compositor written in Janet and Zig"
arch=('x86_64' 'aarch64')
url="https://codeberg.org/ifreund/rijan"
license=('GPL-3.0-only')

# 确保系统中有这些开发库
depends=('wayland' 'libxkbcommon' 'pixman' 'libevdev' 'libinput' 'libffi')
makedepends=('zig>=0.15.0' 'wayland-protocols' 'scdoc' 'pkgconf' 'git')
provides=('rijan')
conflicts=('rijan')

source=("rijan::git+https://codeberg.org/ifreund/rijan.git")
sha256sums=('SKIP')

pkgver() {
  cd "$srcdir/rijan"
  git describe --long --tags --always | sed 's/^v//;s/\([^-]*-g\)/r\1/;s/-/./g'
}

prepare() {
 cd "$srcdir/rijan"

  # 使用 Janet 运行一个简单的字符串替换脚本
  # 我们通过匹配函数头的起始和结束关键行，直接把这些代码块替换为空
  janet -e '
    (var content (file/read (file/open "rijan.janet" :r) :all))
    
    # 定义需要精准剔除的代码片段（直接使用固定字符串匹配）
    (def to-remove [
      # 1. 剔除 bg/manage 函数
      "(defn bg/manage [bg output]\n  (:sync-next-commit (bg :shell-surface))\n  (:place-bottom (bg :node))\n  (:set-position (bg :node) (output :x) (output :y))\n  (def buffer (:create-u32-rgba-buffer\n                (registry \"wp_single_pixel_buffer_manager_v1\")\n                ;(rgb-to-u32-rgba ((wm :config) :background))))\n  (:attach (bg :surface) buffer 0 0)\n  (:damage-buffer (bg :surface) 0 0 0x7fff_ffff 0x7fff_ffff)\n  (:set-destination (bg :viewport) (output :w) (output :h))\n  (:commit (bg :surface))\n  (:destroy buffer))"
      
      # 2. 剔除 bg/destroy 函数
      "(defn bg/destroy [bg]\n  (:destroy (bg :viewport))\n  (:destroy (bg :shell-surface))\n  (:destroy (bg :surface))\n  (:destroy (bg :node)))"
      
      # 3. 剔除 bg/create 函数
      "(defn bg/create []\n  (def surface (:create-surface (registry \"wl_compositor\")))\n  (def viewport (:get-viewport (registry \"wp_viewporter\") surface))\n  (def shell-surface (:get-shell-surface (registry \"river_window_manager_v1\") surface))\n  @{:surface surface\n    :viewport viewport\n    :shell-surface shell-surface\n    :node (:get-node shell-surface)})"
      
      # 4. 剔除调用逻辑
      "(bg/destroy (output :bg))"
      "(bg/manage (output :bg) output)"
      ":bg (bg/create)"
    ])

    (each fragment to-remove
      (set content (string/replace fragment "" content)))

    (file/write (file/open "rijan.janet" :w) content)
    (print "Rijan background logic removed successfully.")
  '

  mkdir -p "$srcdir/zig-cache"
  mkdir -p "$srcdir/zig-local-cache"
}

build() {
  cd "$srcdir/rijan"

  export ZIG_GLOBAL_CACHE_DIR="$srcdir/zig-cache"
  export ZIG_LOCAL_CACHE_DIR="$srcdir/zig-local-cache"

  # 显式指定使用系统 libc
  zig build \
    -Doptimize=ReleaseSafe \
    -Dcpu=baseline \
    --summary all
}

package() {
  cd "$srcdir/rijan"

  export ZIG_GLOBAL_CACHE_DIR="$srcdir/zig-cache"
  export ZIG_LOCAL_CACHE_DIR="$srcdir/zig-local-cache"

  DESTDIR="$pkgdir" zig build \
    -Doptimize=ReleaseSafe \
    -Dcpu=baseline \
    --prefix /usr \
    install

  install -Dm644 LICENSE -t "${pkgdir}/usr/share/licenses/${pkgname}/"
}
