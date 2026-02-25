Tips: 基于我fork的rijan仓库里的源代码(2026年2月5号) 这里有两份rijan源码（都删除了背景色代码方便使用swww展示动图背景），其中rijan.janet（为了区分记录更深入的重构的rijan.janet.patched源码，如果要用这份源码则需改名字为rijan.janet.patched才能结合PKGBUILD进行编译）只是为了正常使用wechat针对xwayland窗口绘制逻辑进行了优化，rijan.janet.patched则深度优化了与waybar结合的焦点不正常问题以及强制平铺有维度约束的xwayland窗口的绘制，同时增加鼠标拖乱多个窗口后一键恢复初始默认平铺布局的快捷键。


rijan.janet文件中，针对xwayland显示问题做了6项修改：
1. seat/focus — 拆分为 seat/resolve-focus-target（纯逻辑）、seat/apply-focus（执行聚焦）、seat/clear-focus（清除聚焦），seat/focus 本身变成了简洁的调度器
2. seat/manage — 拆分为 seat/init-bindings、seat/cleanup-stale-refs、seat/resolve-focus、seat/execute-action、seat/update-op 五个阶段函数，同时消除了那个 TODO 注释（通过引入 op-window 局部变量让意图更清晰）
3. wm/layout — 添加 (when (empty? windows) (break)) 提前返回，side-h/side-h-rem 在 side-count=0 时安全返回 0
4. :true → true — 修复了 window/set-float 和 set-borders 中的关键字拼写错误
5. 删除了全部 bg/* 注释代码块（约30行）
6. wm/manage、wm/render、action/focus-tag、action/toggle-tag、action/focus-all-tags 中的副作用 map 全部替换为 each


rijan.janet.patched文件中全部改动总结
1. 崩溃防护：protect 包裹 manage/render 循环
wm/manage 和 wm/render 的核心逻辑用 (protect ...) 包裹，保证 manage-finish / render-finish 始终被调用。原来任何异常（如 nil 算术）会中断整个事件循环，导致所有快捷键失灵。
2. 崩溃修复：focus-return-to 检查 closed
seat/resolve-focus 中，对 focus-return-to 目标检查 (return-target :closed)，避免对已 destroy 的窗口调用 :focus-window。
3. XWayland 子窗口识别：不依赖 parent，用尺寸判断
新增 window/is-popup-like（两维都固定 min==max）和修改 window/is-fixed-size（任一维度固定）。WeChat 的子窗口 WM_TRANSIENT_FOR 指向 client leader（无对应 wayland surface），导致 window :parent 始终为 nil。改为通过尺寸约束识别 popup 类窗口。
4. 子窗口不加 SSD 和边框
popup-like 窗口标记 managed-as-child，不调用 :use-ssd，window/render 中跳过 set-borders。迟到的 [:parent] 事件也会补上标记。
5. 窗口定位逻辑重写
新增 window/find-logical-parent（按 app-id 找逻辑父窗口）和 window/center-on-output。popup 窗口居中到同 app-id 的主窗口上方，浮动顶层窗口（如朋友圈）居中到 output，不再全部扔到 (0,0)。
6. popup 不抢焦点
seat/resolve-focus 中，managed-as-child 的新窗口只在没有其他 focused 窗口时才获得焦点，避免 WeChat 主界面失焦导致 popup 被关闭（闪退）。
7. 点击 waybar 后焦点恢复
seat/focus 的 :non-exclusive 分支末尾，主动调用 (:focus-window ...) 把焦点从 layer surface 抢回窗口。
8. 平铺布局尊重尺寸约束
新增 clamp-to-hints，wm/layout 分配的 box 尺寸会 clamp 到窗口的 min/max 范围内（box 为硬上限），然后在 box 内居中。朋友圈等受限窗口被强制平铺时不会被拉伸变形。
9. 记录初始尺寸，浮动时恢复
[:dimensions] 事件首次到达时保存 original-w / original-h。action/float 切换回浮动时 propose 回原始尺寸并清除位置让 render 重新居中。
10. 区分用户浮动和程序浮动
seat/pointer-move、seat/pointer-resize、action/float 中，只对原本非浮动的窗口标记 :user-float。程序性浮动（popup、fixed-size）不会被标记。
11. 新增 action/retile
一键把当前 output 上所有 user-float 的窗口恢复平铺，不影响程序性浮动窗口。
12. init.janet 改动
新增快捷键绑定 Super+Shift+R → (action/retile)。






REPL调试命令：`janet -e "(import spork/netrepl) (netrepl/client :unix \"$XDG_RUNTIME_DIR/rijan-$WAYLAND_DISPLAY\")"`


`Ctrl + D` 退出REPL client


`(os/exit)`，`(quit)`退出整个rijan 


>需要安装 janet，janet中用jpm安装spork
