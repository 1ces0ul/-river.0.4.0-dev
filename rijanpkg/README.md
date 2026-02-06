Tips: 基于我fork的rijan仓库里的源代码(2026年2月5号)，为了让swww正常显示背景动图，这个PKGBUILD文件加入了“删除rijan窗口管理器的源代码中固定颜色背景部分的代码“的代码。

REPL调试命令：`janet -e "(import spork/netrepl) (netrepl/client :unix \"$XDG_RUNTIME_DIR/rijan-$WAYLAND_DISPLAY\")"`


`Ctrl + D` 退出REPL client


`(os/exit)`，`(quit)`退出整个rijan 


>需要安装 janet，janet中用jpm安装spork
