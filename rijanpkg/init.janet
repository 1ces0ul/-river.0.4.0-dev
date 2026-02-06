# ============================================================
# 1. 常量与环境路径 (单一事实来源)
# ============================================================
(def- home (os/getenv "HOME"))

(def paths {
  :waybar-conf (string home "/.config/river/statusbar/waybar/config.json")
  :waybar-css  (string home "/.config/river/statusbar/waybar/river_style.css")
  :wallpaper   (string home "/.config/river/wallpapers/blackhole.gif")
  :dunst-conf  (string home "/.config/dunst/dunstrc")
})

# ============================================================
# 2. 核心工具函数 (通知、重载与容错)
# ============================================================

# [桌面通知]
(defn- notify [msg &opt title level]
  (default title "Rijan 系统")
  (default level "normal")
  (os/spawn ["notify-send" "-a" "Rijan" "-u" level title msg] :p))

# [Waybar 启动指令定义]
(def waybar-cmd (string "waybar -c " (paths :waybar-conf) " -s " (paths :waybar-css)))

# ============================================================
# 3. 按键绑定 (声明式逻辑)
# ============================================================
(array/push
  (config :xkb-bindings)
  # --- Waybar Toggle (最优解：信号隐藏 || 失败救活)
  [:b {:mod4 true :shift true} (action/spawn ["sh" "-c" (string "pkill -USR1 waybar || " waybar-cmd " &")])]
  [:XF86MonBrightnessUp {} (action/spawn ["brightnessctl" "set" "10%+"])]
  [:XF86MonBrightnessDown {} (action/spawn ["brightnessctl" "set" "10%-"])]
  [:XF86AudioRaiseVolume {} (action/spawn ["wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%+" "-l" "1"])]
  [:XF86AudioLowerVolume {} (action/spawn ["wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-" "-l" "1"])]
  [:XF86AudioMute {} (action/spawn ["wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"])]
  [:XF86AudioMicMute {} (action/spawn ["wpctl" "set-mute" "@DEFAULT_AUDIO_SOURCE@" "toggle"])]
  [:XF86AudioPause {} (action/spawn ["playerctl" "play-pause"])]
  [:XF86AudioPlay {} (action/spawn ["playerctl" "play-pause"])]
  [:XF86AudioNext {} (action/spawn ["playerctl" "next"])]
  [:XF86AudioPrev {} (action/spawn ["playerctl" "previous"])]
  [:XF86Eject {} (action/spawn ["eject" "-T"])]
  [:0x1008ff41 {} (action/spawn ["chromium"])]
  [:b {:mod4 true} (action/spawn ["chromium"])]
  [:t {:mod4 true} (action/spawn ["kitty"])]
  [:r {:mod4 true} (action/spawn ["rofi" "-show" "drun"])]
  [:q {:mod4 true} (action/close)]
  [:space {:mod4 true} (action/zoom)]
  [:p {:mod4 true} (action/focus :prev)]
  [:n {:mod4 true} (action/focus :next)]
  [:k {:mod4 true} (action/focus-output)]
  [:j {:mod4 true} (action/focus-output)]
  [:f {:mod4 true} (action/fullscreen)]
  [:f {:mod4 true :mod1 true} (action/float)]
  [:a {:mod4 true} (action/spawn ["sh" "-c" "grim -g \"$(slurp)\" - | wl-copy"])]
  [:Escape {:mod4 true :mod1 true :shift true :ctrl true} (action/passthrough)]
  [:0 {:mod4 true} (action/focus-all-tags)])

# [工作区 1-10 自动化循环生成]
(for i 1 10
  (let [tag (keyword i)]
    (array/push (config :xkb-bindings)
      [tag {:mod4 true} (action/focus-tag i)]
      [tag {:mod4 true :mod1 true} (action/set-tag i)]
      [tag {:mod4 true :mod1 true :shift true} (action/toggle-tag i)])))

(array/push
  (config :pointer-bindings)
  [:left {:mod4 :true} (action/pointer-move)]
  [:right {:mod4 :true} (action/pointer-resize)])
# ============================================================
# 4. 幂等性自启动序列 (防止重复进程)
# ============================================================
# 将所有环境同步和启动逻辑打包进一个后台 Shell 进程
# 这样做 Janet 瞬间就执行完了，不会产生 Broken Pipe
(os/spawn ["sh" "-c" (string
  # 1. 第一步：同步环境（这是所有图形程序的基石）
  "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP DISPLAY; "
  
  # 2. 第二步：启动不依赖环境的程序（并行）
  "pgrep -x fcitx5 > /dev/null || fcitx5 -d & "
  
  # 3. 第三步：启动依赖环境的程序（串行链条，确保变量已生效）
  # 使用 && 确保前一步成功才执行下一步
  "systemctl --user restart swww.service && "
  "swww img " (paths :wallpaper) " & "
  
  # 4. 状态栏和通知
  "pgrep -x waybar > /dev/null || " waybar-cmd " & "
  "pgrep -x dunst > /dev/null || dunst -config " (paths :dunst-conf) " & "
)] :p)

# [初始化完成通知]
(notify "所有服务已就绪" "Rijan 启动完成")
