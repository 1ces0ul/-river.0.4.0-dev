Tips: 基于我fork的rijan仓库里的源代码(2026年2月5号) 这里有两份rijan源码（都删除了背景色代码方便使用swww展示动图背景），其中rijan.janet是最新的在rijan.janet.patched基础上更深入的窗口绘制逻辑升级并增加了grid，scroller布局，rijan.janet.patched是在原版rijan基础上的xwayland窗口绘制逻辑进行了优化。init.janet是针对最新的rijan.janet配置的，rijan.janet.patched仅用于历史记录。

REPL调试命令：`janet -e "(import spork/netrepl) (netrepl/client :unix \"$XDG_RUNTIME_DIR/rijan-$WAYLAND_DISPLAY\")"`


`Ctrl + D` 退出REPL client


`(os/exit)`，`(quit)`退出整个rijan 


>需要安装 janet，janet中用jpm安装spork
