Tips: 基于我fork的rijan仓库里的源代码(2026年2月5号)，为了让swww正常显示背景动图，这个PKGBUILD文件用patch文件
全部6项修改：
1. seat/focus — 拆分为 seat/resolve-focus-target（纯逻辑）、seat/apply-focus（执行聚焦）、seat/clear-focus（清除聚焦），seat/focus 本身变成了简洁的调度器
2. seat/manage — 拆分为 seat/init-bindings、seat/cleanup-stale-refs、seat/resolve-focus、seat/execute-action、seat/update-op 五个阶段函数，同时消除了那个 TODO 注释（通过引入 op-window 局部变量让意图更清晰）
3. wm/layout — 添加 (when (empty? windows) (break)) 提前返回，side-h/side-h-rem 在 side-count=0 时安全返回 0
4. :true → true — 修复了 window/set-float 和 set-borders 中的关键字拼写错误
5. 删除了全部 bg/* 注释代码块（约30行）
6. wm/manage、wm/render、action/focus-tag、action/toggle-tag、action/focus-all-tags 中的副作用 map 全部替换为 each

REPL调试命令：`janet -e "(import spork/netrepl) (netrepl/client :unix \"$XDG_RUNTIME_DIR/rijan-$WAYLAND_DISPLAY\")"`


`Ctrl + D` 退出REPL client


`(os/exit)`，`(quit)`退出整个rijan 


>需要安装 janet，janet中用jpm安装spork
