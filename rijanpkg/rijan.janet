(import protocols)
(import wayland)
(import spork/netrepl)
(import xkbcommon)

(def interfaces
  (wayland/scan
    :wayland-xml protocols/wayland-xml
    :system-protocols-dir protocols/wayland-protocols
    :system-protocols ["stable/viewporter/viewporter.xml"
                       "staging/single-pixel-buffer/single-pixel-buffer-v1.xml"]
    :custom-protocols (map |(string protocols/river-protocols $)
                           ["/river-window-management-v1.xml"
                            "/river-layer-shell-v1.xml"
                            "/river-xkb-bindings-v1.xml"])))

(def required-interfaces
  @{"wl_compositor" 4
    "wp_viewporter" 1
    "wp_single_pixel_buffer_manager_v1" 1
    "river_window_manager_v1" 2
    "river_layer_shell_v1" 1
    "river_xkb_bindings_v1" 1})

# https://protesilaos.com/emacs/modus-themes-colors
(def light @{:background 0xffffff
             :border-normal 0x000000
             :border-focused 0x9e9e9e})

(def dark @{:background 0x000000
            :border-normal 0x646464
            :border-focused 0xffffff})

(def config @{:border-width 2
              :outer-padding 4
              :inner-padding 4
              :main-ratio 0.60
              :nmaster 1
              :xkb-bindings @[]
              :pointer-bindings @[]})
(merge-into config light)

(def wm @{:config config
          :outputs @[]
          :seats @[]
          :windows @[]
          # Windows in rendering order rather than window management order.
          # The last window in the array is rendered on top.
          :render-order @[]})

(def registry @{})

(defn rgb-to-u32-rgba [rgb]
  [(* (band 0xff (brushift rgb 16)) (/ 0xffff_ffff 0xff))
   (* (band 0xff (brushift rgb 8)) (/ 0xffff_ffff 0xff))
   (* (band 0xff rgb) (/ 0xffff_ffff 0xff))
   0xffff_ffff])

(defn output/visible [output windows]
  (let [tags (output :tags)]
    (filter |(or ($ :sticky) (tags ($ :tag))) windows)))

(defn output/usable-area [output]
  (if-let [[x y w h] (output :non-exclusive-area)]
    {:x x :y y :w w :h h}
    {:x (output :x) :y (output :y) :w (output :w) :h (output :h)}))

(defn output/manage-start [output]
  (if (output :removed)
    (:destroy (output :obj))
    output))

(defn output/manage [output]
  (when (output :new)
    (let [unused (find (fn [tag] (not (find |(($ :tags) tag) (wm :outputs)))) (range 1 10))]
      (put (output :tags) unused true))))

(defn output/manage-finish [output]
  (put output :new nil))

(defn output/create [obj]
  (def output @{:obj obj
                :layer-shell (:get-output (registry "river_layer_shell_v1") obj)
                :new true
                :tags @{}})
  (defn output/handle-event [event]
    (match event
      [:removed] (put output :removed true)
      [:position x y] (do (put output :x x) (put output :y y))
      [:dimensions w h] (do (put output :w w) (put output :h h))))
  (defn output/handle-layer-shell-event [event]
    (match event
      [:non-exclusive-area x y w h] (put output :non-exclusive-area [x y w h])))
  (:set-user-data obj output)
  (:set-handler obj output/handle-event)
  (:set-handler (output :layer-shell) output/handle-layer-shell-event)
  output)

(defn window/set-position
  "Set position. Stores the layout coordinate (without border offset) in
   window :x/:y, and passes the border-adjusted value to the compositor."
  [window x y]
  (let [border-width ((wm :config) :border-width)]
    (put window :x x)
    (put window :y y)
    (:set-position (window :node) (+ x border-width) (+ y border-width))))

(defn window/propose-dimensions
  "Propose dimensions, adjusting for border width"
  [window w h]
  (def border-width ((wm :config) :border-width))
  (:propose-dimensions (window :obj)
                       (max 1 (- w (* 2 border-width)))
                       (max 1 (- h (* 2 border-width)))))

(defn window/set-float [window float]
  (if float
    (:set-tiled (window :obj) {})
    (:set-tiled (window :obj) {:left true :bottom true :top true :right true}))
  (put window :float float))

(defn window/set-fullscreen [window fullscreen-output]
  (if-let [output fullscreen-output]
    (do
      (put window :fullscreen true)
      (:inform-fullscreen (window :obj))
      (:fullscreen (window :obj) (output :obj)))
    (do
      (put window :fullscreen false)
      (:inform-not-fullscreen (window :obj))
      (:exit-fullscreen (window :obj)))))

(defn window/tag-output [window]
  (or (find |(($ :tags) (window :tag)) (wm :outputs))
      (when (window :sticky)
        (when-let [seat (first (wm :seats))]
          (seat :focused-output)))))

(defn window/max-overlap-output [window]
  (var max-overlap 0)
  (var max-overlap-output nil)
  (def bw2 (* 2 ((wm :config) :border-width)))
  (each output (wm :outputs)
    (def overlap-w (- (min (+ (window :x) (window :w) bw2)
                           (+ (output :x) (output :w)))
                      (max (window :x) (output :x))))
    (def overlap-h (- (min (+ (window :y) (window :h) bw2)
                           (+ (output :y) (output :h)))
                      (max (window :y) (output :y))))
    (when (and (> overlap-w 0) (> overlap-h 0))
      (def overlap (* overlap-w overlap-h))
      (when (> overlap max-overlap)
        (set max-overlap overlap)
        (set max-overlap-output output))))
  max-overlap-output)

(defn window/update-tag [window]
  (when-let [output (window/max-overlap-output window)]
    (unless (= output (window/tag-output window))
      (put window :tag (or (min-of (keys (output :tags))) 1)))))

(defn window/create [obj]
  (def window @{:obj obj
                :node (:get-node obj)
                :new true
                :tag 1})
  (defn window/handle-event [event]
    (match event
      [:closed] (put window :closed true)
      [:dimensions-hint min-w min-h max-w max-h] (do
                                                   (put window :min-w min-w)
                                                   (put window :min-h min-h)
                                                   (put window :max-w max-w)
                                                   (put window :max-h max-h))
      [:dimensions w h] (do (put window :w w) (put window :h h)
                            (unless (window :original-w)
                              (put window :original-w w)
                              (put window :original-h h)))
      [:app-id app-id] (put window :app-id app-id)
      [:title title] (put window :title title)
      [:parent parent] (do (put window :parent-event-received true)
                           (put window :parent (if parent (:get-user-data parent))))
      [:decoration-hint hint] (put window :decoration-hint hint)
      [:pointer-move-requested seat] (put window :pointer-move-requested
                                          {:seat (:get-user-data seat)})
      [:pointer-resize-requested seat edges] (put window :pointer-resize-requested
                                                  {:seat (:get-user-data seat)
                                                   :edges edges})
      [:fullscreen-requested output] (put window :fullscreen-requested
                                          [:enter (if output (:get-user-data output))])
      [:exit-fullscreen-requested] (put window :fullscreen-requested [:exit])))
  (:set-handler obj window/handle-event)
  (:set-user-data obj window)
  window)

(defn pointer-binding/create [seat button mods action]
  # From /usr/include/linux/input-event-codes.h
  (def button-code {:left 0x110
                    :right 0x111
                    :middle 0x112})
  (def binding @{:obj (:get-pointer-binding (seat :obj) (button-code button) mods)})
  (defn handle-event [event]
    (match event
      [:pressed] (put seat :pending-action [binding action])))
  (:set-handler (binding :obj) handle-event)
  (:enable (binding :obj))
  (array/push (seat :pointer-bindings) binding))

(defn xkb-binding/create [seat keysym mods action]
  (def binding @{:obj (:get-xkb-binding (registry "river_xkb_bindings_v1")
                                        (seat :obj) (xkbcommon/keysym keysym) mods)})
  (defn handle-event [event]
    (match event
      [:pressed] (put seat :pending-action [binding action])))
  (:set-handler (binding :obj) handle-event)
  (:enable (binding :obj))
  (array/push (seat :xkb-bindings) binding))

(defn seat/focus-output [seat output]
  (unless (= output (seat :focused-output))
    (put seat :focused-output output)
    (when output (:set-default (output :layer-shell)))))

(defn- seat/resolve-focus-target
  "Determine which window should be focused, or :clear to clear focus, or :keep to keep current.
   Returns the target window, :clear, or :keep."
  [seat window]
  (when-let [output (seat :focused-output)]
    (defn visible? [w] (and w (or (w :sticky) ((output :tags) (w :tag)))))
    (def visible (output/visible output (wm :render-order)))
    (cond
      # The top fullscreen window always grabs focus when present.
      (def fullscreen (last (filter |($ :fullscreen) visible)))
      fullscreen
      # If there is a visible explicit target window, focus it.
      (visible? window) window
      # Otherwise, don't change focus if the current focus is visible.
      (visible? (seat :focused)) :keep
      # When no visible window is focused, focus the top one, if any.
      (def top-visible (last visible)) top-visible
      # When no windows are visible, clear focus.
      :clear)))

(defn- seat/apply-focus
  "Apply focus to a window, updating render order and compositor state."
  [seat window]
  (unless (= (seat :focused) window)
    (:focus-window (seat :obj) (window :obj))
    (put seat :focused window)
    (if-let [i (find-index |(= $ window) (wm :render-order))]
      (array/remove (wm :render-order) i))
    (array/push (wm :render-order) window)
    (:place-top (window :node))))

(defn- seat/clear-focus [seat]
  (when (seat :focused)
    (:clear-focus (seat :obj))
    (put seat :focused nil)))

(defn seat/focus [seat window]
  (defn focus-non-layer []
    (when window
      (when-let [output (window/tag-output window)]
        (seat/focus-output seat output)))
    (def target (seat/resolve-focus-target seat window))
    (case target
      nil    (do)
      :keep  (do)
      :clear (seat/clear-focus seat)
      (seat/apply-focus seat target)))
  (case (seat :layer-focus)
    :exclusive (put seat :focused nil)
    :non-exclusive (do
                     (when window
                       (put seat :layer-focus :none))
                     (focus-non-layer)
                     # After non-exclusive layer interaction (e.g. clicking waybar),
                     # the compositor has given focus to the layer surface.
                     # Re-assert focus on the current window so the compositor
                     # sends keyboard events back to it.
                     (when-let [focused (seat :focused)]
                       (:focus-window (seat :obj) (focused :obj))))
    :none (focus-non-layer)))

(defn seat/pointer-move [seat window]
  (unless (seat :op)
    (seat/focus seat window)
    (unless (window :float)
      (put window :user-float true))
    (window/set-float window true)
    (:op-start-pointer (seat :obj))
    (put seat :op @{:type :move
                    :window window
                    :start-x (window :x) :start-y (window :y)
                    :dx 0 :dy 0})))

(defn seat/pointer-resize [seat window edges]
  (unless (seat :op)
    (seat/focus seat window)
    (unless (window :float)
      (put window :user-float true))
    (window/set-float window true)
    (:op-start-pointer (seat :obj))
    (put seat :op @{:type :resize
                    :window window
                    :edges edges
                    :start-x (window :x) :start-y (window :y)
                    :start-w (window :w) :start-h (window :h)
                    :dx 0 :dy 0})))

(defn window/manage-start [window]
  (if (window :closed)
    (do
      (:destroy (window :obj))
      (:destroy (window :node)))
    window))

(defn window/is-partially-fixed [window]
  "True when exactly one dimension is fixed (min == max, non-zero)
   but the other is not. Indicates a window that shouldn't be tiled
   (e.g. Moments: width fixed, height flexible)."
  (def w-fixed (and (window :min-w) (window :max-w)
                    (> (window :min-w) 0) (> (window :max-w) 0)
                    (= (window :min-w) (window :max-w))))
  (def h-fixed (and (window :min-h) (window :max-h)
                    (> (window :min-h) 0) (> (window :max-h) 0)
                    (= (window :min-h) (window :max-h))))
  (and (or w-fixed h-fixed)
       (not (and w-fixed h-fixed))))

(defn window/manage [window]
  (when (window :new)
    (if (window :parent-event-received)
      # Received parent event (WM_TRANSIENT_FOR exists) → transient window.
      # This includes both real parent and client leader (transient → nil).
      (do
        (put window :managed-as-child true)
        (window/set-float window true)
        (if (and (window :parent)
                 (window :w) (> (window :w) 0)
                 (window :h) (> (window :h) 0))
          (:propose-dimensions (window :obj) (window :w) (window :h))
          (if (and (window :min-w) (> (window :min-w) 0)
                   (window :min-h) (> (window :min-h) 0))
            (:propose-dimensions (window :obj) (window :min-w) (window :min-h))
            (:propose-dimensions (window :obj) 0 0)))
        (when-let [parent (window :parent)]
          (put window :tag (parent :tag))))
      # No parent event received → independent top-level window.
      (do
        (:use-ssd (window :obj))
        (if (window/is-partially-fixed window)
          (window/set-float window true)
          (window/set-float window false))
        (when-let [seat (first (wm :seats))
                   output (seat :focused-output)]
          (put window :tag (or (min-of (keys (output :tags))) 1))))))
  # Late-arriving parent: convert to child if parent appears after first cycle.
  (when (and (not (window :new))
             (window :parent)
             (not (window :managed-as-child)))
    (put window :managed-as-child true)
    (window/set-float window true)
    (put window :tag ((window :parent) :tag)))
  (match (window :fullscreen-requested)
    [:enter] (if-let [seat (first (wm :seats))
                       output (seat :focused-output)]
               (window/set-fullscreen window output))
    [:enter output] (window/set-fullscreen window output)
    [:exit] (window/set-fullscreen window nil))
  (when-let [move (window :pointer-move-requested)]
    (seat/pointer-move (move :seat) window))
  (when-let [resize (window :pointer-resize-requested)]
    (seat/pointer-resize (resize :seat) window (resize :edges))))

(defn window/manage-finish [window]
  (put window :new nil)
  (put window :pointer-move-requested nil)
  (put window :pointer-resize-requested nil)
  (put window :fullscreen-requested nil))

(defn- window/find-logical-parent [window]
  "For popup-like windows whose WM_TRANSIENT_FOR points to a client leader
   (so window :parent is nil), find the most likely logical parent by
   matching app-id among existing visible non-child windows."
  (when-let [app-id (window :app-id)]
    (find |(and (not ($ :managed-as-child))
               (not ($ :closed))
               (= ($ :app-id) app-id)
               ($ :x) ($ :w))
          (wm :windows))))

(defn- window/center-on-output [window]
  "Center window on the focused output's usable area, or fall back to 0,0."
  (if-let [seat (first (wm :seats))
           output (seat :focused-output)]
    (let [usable (output/usable-area output)
          bw2 (* 2 ((wm :config) :border-width))]
      (window/set-position window
                           (+ (usable :x) (div (- (usable :w) (window :w) bw2) 2))
                           (+ (usable :y) (div (- (usable :h) (window :h) bw2) 2))))
    (window/set-position window 0 0)))

(defn- set-borders [window status config]
  (def rgb (case status
             :normal (config :border-normal)
             :focused (config :border-focused)))
  (:set-borders (window :obj)
                {:left true :bottom true :top true :right true}
                (config :border-width)
                ;(rgb-to-u32-rgba rgb)))

(defn window/render [window]
  (when (and (not (window :x)) (window :w))
    (def bw ((wm :config) :border-width))
    (if-let [parent (window :parent)]
      # Has a real parent — center over parent's content area, or fall back to output center.
      (if (and (parent :x) (parent :y) (parent :w) (parent :h))
        (window/set-position window
                             (+ (parent :x) bw (div (- (parent :w) (window :w)) 2))
                             (+ (parent :y) bw (div (- (parent :h) (window :h)) 2)))
        (window/center-on-output window))
      # No parent.
      (if (window :managed-as-child)
        # Popup-like window (no real parent due to XWayland client leader).
        # Try to find a logical parent by app-id and center over its content area.
        (if-let [logical-parent (window/find-logical-parent window)]
          (window/set-position window
                               (+ (logical-parent :x) bw
                                  (div (- (logical-parent :w) (window :w)) 2))
                               (+ (logical-parent :y) bw
                                  (div (- (logical-parent :h) (window :h)) 2)))
          (window/center-on-output window))
        # Floating top-level (e.g. Moments) — center on output.
        (if (window :float)
          (window/center-on-output window)
          # Tiled windows get positioned by wm/layout, not here.
          (window/set-position window 0 0)))))
  # Ensure child windows are always rendered above their parent.
  (when-let [parent (window :parent)]
    (unless (parent :closed)
      (def parent-idx (find-index |(= $ parent) (wm :render-order)))
      (def window-idx (find-index |(= $ window) (wm :render-order)))
      (when (and parent-idx window-idx (< window-idx parent-idx))
        # Child is below parent in render order — move it above.
        (array/remove (wm :render-order) window-idx)
        (array/push (wm :render-order) window)
        (:place-top (window :node)))))
  # Child/transient windows get no borders.
  (unless (window :managed-as-child)
    (if (find |(= ($ :focused) window) (wm :seats))
      (set-borders window :focused (wm :config))
      (set-borders window :normal (wm :config))))
  # Clip tiled windows to their allocated layout box so that windows
  # whose actual size exceeds the proposed size don't visually overflow.
  (if-let [box (window :layout-box)]
    (let [[box-x box-y box-w box-h] box
          bw ((wm :config) :border-width)]
      (:set-clip-box (window :obj)
                     (- box-x (window :x) bw)
                     (- box-y (window :y) bw)
                     box-w box-h))
    (:set-clip-box (window :obj) 0 0 0 0)))

(defn seat/manage-start [seat]
  (if (seat :removed)
    (:destroy (seat :obj))
    seat))

(defn- seat/init-bindings [seat]
  "Initialize key and pointer bindings for a new seat."
  (when (seat :new)
    (each binding (config :xkb-bindings)
      (xkb-binding/create seat ;binding))
    (each binding (config :pointer-bindings)
      (pointer-binding/create seat ;binding))))

(defn- seat/cleanup-stale-refs [seat]
  "Clear references to closed windows and removed outputs.
   When a child window closes, schedule focus return to its parent."
  (when-let [window (seat :focused)]
    (when (window :closed)
      # If the closed window has a parent that is still alive,
      # remember it so we can return focus to it.
      (if-let [parent (window :parent)]
        (unless (parent :closed)
          (put seat :focus-return-to parent)))
      (put seat :focused nil)))
  (when-let [op (seat :op)]
    (when ((op :window) :closed)
      (put seat :op nil)))
  (if (or (not (seat :focused-output))
          ((seat :focused-output) :removed))
    (seat/focus-output seat (first (wm :outputs)))))

(defn- seat/resolve-focus [seat]
  "Determine and apply focus: existing windows, new windows, interactions.
   Prioritizes: focus-return-to (parent of closed child) > new windows > interaction."
  # If a child window just closed, try to return focus to its parent first.
  # But only if the parent is still alive — it may have been destroyed in
  # the same manage cycle (e.g. WeChat login flash: parent and child both close).
  (if-let [return-target (seat :focus-return-to)]
    (do
      (put seat :focus-return-to nil)
      (if (return-target :closed)
        (seat/focus seat nil)
        (seat/focus seat return-target)))
    (seat/focus seat nil))
  (each window (wm :windows)
    (when (window :new)
      # Popup-like windows (managed-as-child) should not steal focus from
      # an existing focused window — they expect focus to stay on the main
      # window. But if nothing is focused (e.g. login window is the only
      # window), they should receive focus.
      (unless (and (window :managed-as-child) (seat :focused))
        (seat/focus seat window))))
  (if-let [window (seat :window-interaction)]
    (seat/focus seat window)))

(defn- seat/execute-action [seat]
  "Execute the pending keybinding/pointer action, then re-sync focus."
  (when-let [[binding action] (seat :pending-action)]
    (action seat binding))
  # Ensure focus is consistent after action (e.g. may have switched tags)
  (seat/focus seat nil))

(defn- seat/update-op [seat]
  "Handle ongoing pointer operations (resize) and op-release finalization."
  (when-let [op (seat :op)]
    (when (= :resize (op :type))
      (window/propose-dimensions (op :window)
                                 (max 1 (+ (op :start-w) (op :dx)))
                                 (max 1 (+ (op :start-h) (op :dy))))))
  (when (and (seat :op-release) (seat :op))
    (:op-end (seat :obj))
    (def op-window ((seat :op) :window))
    (window/update-tag op-window)
    (seat/focus-output seat (window/tag-output op-window))
    (put seat :op nil)))

(defn seat/manage [seat]
  (seat/init-bindings seat)
  (seat/cleanup-stale-refs seat)
  (seat/resolve-focus seat)
  (seat/execute-action seat)
  (seat/update-op seat))

(defn seat/manage-finish [seat]
  (put seat :new nil)
  (put seat :window-interaction nil)
  (put seat :pending-action nil)
  (put seat :op-release nil)
  (put seat :focus-return-to nil))

(defn seat/render [seat]
  (when-let [op (seat :op)]
    (when (= :move (op :type))
      (window/set-position (op :window)
                           (+ (op :start-x) (op :dx))
                           (+ (op :start-y) (op :dy))))))

(defn seat/create [obj]
  (def seat @{:obj obj
              :layer-shell (:get-seat (registry "river_layer_shell_v1") obj)
              :layer-focus :none
              :xkb-bindings @[]
              :pointer-bindings @[]
              :new true})
  (defn seat/handle-event [event]
    (match event
      [:removed] (put seat :removed true)
      [:pointer-enter window] (put seat :pointer-target (:get-user-data window))
      [:pointer-leave] (put seat :pointer-target nil)
      [:window-interaction window] (put seat :window-interaction (:get-user-data window))
      [:shell-surface-interaction shell_surface] (do)
      [:op-delta dx dy] (do (put (seat :op) :dx dx) (put (seat :op) :dy dy))
      [:op-release] (put seat :op-release true)))
  (defn seat/handle-layer-shell-event [event]
    (match event
      [:focus-exclusive] (put seat :layer-focus :exclusive)
      [:focus-non-exclusive] (put seat :layer-focus :non-exclusive)
      [:focus-none] (put seat :layer-focus :none)))
  (:set-handler obj seat/handle-event)
  (:set-handler (seat :layer-shell) seat/handle-layer-shell-event)
  (:set-user-data obj seat)
  (:set-xcursor-theme obj "Adwaita" 24)
  seat)

(defn wm/show-hide []
  (def all-tags @{})
  (each output (wm :outputs)
    (merge-into all-tags (output :tags))
    # Ensure the output on which windows are fullscreen is updated
    # if they become visible on a different output.
    (each window (wm :windows)
      (when (and (window :fullscreen)
                 ((output :tags) (window :tag)))
        (:fullscreen (window :obj) (output :obj)))))
  (each window (wm :windows)
    (if (window :layout-hidden)
      (:hide (window :obj))
      (if (or (window :sticky) (all-tags (window :tag)))
        (:show (window :obj))
        (:hide (window :obj))))))

(defn- clamp-to-hints [window box-x box-y box-w box-h]
  "Constrain window dimensions to its min/max size hints, but never
   exceed the allocated box. The box (layout space) is the hard limit;
   the window's hints are best-effort. Center the result in the box.
   Hints are content sizes (no border); box is layout size (with border)."
  (def bw2 (* 2 ((wm :config) :border-width)))
  (var w box-w)
  (var h box-h)
  # Shrink to max if smaller than box (convert content hint to layout space)
  (when (and (window :max-w) (> (window :max-w) 0))
    (set w (min w (+ (window :max-w) bw2))))
  (when (and (window :max-h) (> (window :max-h) 0))
    (set h (min h (+ (window :max-h) bw2))))
  # Expand to min, but never exceed box
  (when (and (window :min-w) (> (window :min-w) 0))
    (set w (min box-w (max w (+ (window :min-w) bw2)))))
  (when (and (window :min-h) (> (window :min-h) 0))
    (set h (min box-h (max h (+ (window :min-h) bw2)))))
  # Center within box
  (def cx (+ box-x (div (- box-w w) 2)))
  (def cy (+ box-y (div (- box-h h) 2)))
  [cx cy w h])


# --- Layout engines ---

(defn layout/master-stack
  "Master-stack with configurable direction. location: :left :right :top :bottom"
  [windows usable cfg location]
  (when (empty? windows) (break @[]))
  (def n (length windows))
  (def nmaster (min n (max 1 (or (cfg :nmaster) 1))))
  (def side-count (- n nmaster))
  (def outer (cfg :outer-padding))
  (def inner (cfg :inner-padding))
  (def [total-w total-h]
    (let [w (max 0 (- (usable :w) (* 2 outer)))
          h (max 0 (- (usable :h) (* 2 outer)))]
      (if (or (= location :top) (= location :bottom)) [h w] [w h])))
  (def main-w (if (= 0 side-count) total-w (math/round (* total-w (cfg :main-ratio)))))
  (def side-w (- total-w main-w))
  (def master-h (if (= 0 nmaster) 0 (div total-h nmaster)))
  (def master-h-rem (if (= 0 nmaster) 0 (% total-h nmaster)))
  (def side-h (if (= 0 side-count) 0 (div total-h side-count)))
  (def side-h-rem (if (= 0 side-count) 0 (% total-h side-count)))
  (seq [i :range [0 n]]
    (def [rx ry rw rh]
      (if (< i nmaster)
        # Master area
        (let [y (+ (* i master-h) (if (> i 0) (+ master-h-rem inner) 0))
              w (if (> side-count 0) (- main-w (div inner 2)) main-w)
              h (- (+ master-h (if (= i 0) master-h-rem 0)) (if (> i 0) inner 0))]
          [0 y w h])
        # Stack area
        (let [si (- i nmaster)
              y (+ (* si side-h) (if (> si 0) (+ side-h-rem inner) 0))
              w (- side-w (div inner 2))
              h (- (+ side-h (if (= si 0) side-h-rem 0)) (if (> si 0) inner 0))]
          [(+ main-w (div inner 2)) y w h])))
    # Apply outer + inner padding
    (def [rx ry rw rh]
      [(+ rx outer inner) (+ ry outer inner)
       (- rw (* 2 inner)) (- rh (* 2 inner))])
    # Map to screen coordinates; :right/:bottom mirror :left/:top
    (case location
      :left   [(+ rx (usable :x))
               (+ ry (usable :y))
               rw rh]
      :right  [(+ (- (usable :w) rx rw) (usable :x))
               (+ ry (usable :y))
               rw rh]
      :top    [(+ ry (usable :x))
               (+ rx (usable :y))
               rh rw]
      :bottom [(+ ry (usable :x))
               (+ (- (usable :h) rx rw) (usable :y))
               rh rw])))

(defn layout/scroller
  "Scroller: focused window centered, neighbors extend outward with same mfact width.
   Windows beyond screen edge are hidden. Inspired by kwm scroller.zig."
  [windows usable cfg focused-window]
  (when (empty? windows) (break @[]))
  (def outer (cfg :outer-padding))
  (def inner (cfg :inner-padding))
  (def avail-w (max 0 (- (usable :w) (* 2 outer))))
  (def avail-h (max 0 (- (usable :h) (* 2 outer))))
  (def mfact (or (cfg :scroller-mfact) (cfg :main-ratio)))
  (def location (or (cfg :scroller-location) :center))
  (def focus-idx (or (index-of focused-window windows)
                     # focused window might be floating; find nearest tiled neighbor
                     0))
  (def n (length windows))
  (def master-w (math/round (* avail-w mfact)))
  (def master-x
    (case location
      :center (div (- avail-w master-w) 2)
      :left 0
      0))
  (def y (+ outer (usable :y)))
  (def x-off (+ outer (usable :x)))

  (def result (array/new-filled n nil))

  # Place focused window
  (put result focus-idx
       [(+ master-x x-off) y master-w avail-h])

  # Place windows to the left of focus
  (var x master-x)
  (var left-hidden false)
  (for i 0 focus-idx
    (def wi (- focus-idx 1 i))
    (def w (math/round (* avail-w mfact)))
    (set x (- x inner))
    (if (or left-hidden (< x 0))
      (do (set left-hidden true)
          (put result wi :hide))
      (do
        (set x (- x w))
        (put result wi [(+ x x-off) y w avail-h]))))

  # Place windows to the right of focus
  (set x (+ master-x master-w))
  (var right-hidden false)
  (for i (+ focus-idx 1) n
    (set x (+ x inner))
    (def w (math/round (* avail-w mfact)))
    (if (or right-hidden (>= x avail-w))
      (do (set right-hidden true)
          (put result i :hide))
      (do
        (put result i [(+ x x-off) y w avail-h])
        (set x (+ x w)))))

  # Apply inner padding to each visible window to match master-stack/grid behavior
  (map |(if (= $ :hide) :hide
          (let [[bx by bw bh] $]
            [(+ bx inner) (+ by inner) (- bw (* 2 inner)) (- bh (* 2 inner))]))
       result))

(defn layout/grid
  "Grid layout."
  [windows usable cfg]
  (when (empty? windows) (break @[]))
  (def n (length windows))
  (def outer (cfg :outer-padding))
  (def inner (cfg :inner-padding))
  (def cols (math/ceil (math/sqrt n)))
  (def rows (math/ceil (/ n cols)))
  (def avail-w (max 0 (- (usable :w) (* 2 outer))))
  (def avail-h (max 0 (- (usable :h) (* 2 outer))))
  (def cell-w (div avail-w cols))
  (def cell-w-rem (% avail-w cols))
  (def cell-h (div avail-h rows))
  (def cell-h-rem (% avail-h rows))
  (def last-row-count (- n (* (- rows 1) cols)))
  (def last-row-pad (div (* (- cols last-row-count) cell-w) 2))
  (seq [i :range [0 n]]
    (def row (div i cols))
    (def col (% i cols))
    (def x (+ (* col cell-w) (if (> col 0) cell-w-rem 0)
              (if (= row (- rows 1)) last-row-pad 0)))
    (def y (+ (* row cell-h) (if (> row 0) (+ inner cell-h-rem) 0)))
    (def w (- (+ cell-w (if (= col 0) cell-w-rem 0))
              (if (< col (- cols 1)) inner 0)))
    (def h (- (+ cell-h (if (= row 0) cell-h-rem 0))
              (if (> row 0) inner 0)))
    # Apply inner padding to match master-stack behavior
    [(+ x outer inner (usable :x)) (+ y outer inner (usable :y))
     (- w (* 2 inner)) (- h (* 2 inner))]))

(defn wm/layout [output]
  (def layout-type (or (output :layout) :tile))
  (def all-visible (output/visible output (wm :windows)))
  # Clear transient layout state for all visible windows on this output,
  # so switching layouts doesn't leave stale marks or clip boxes.
  (each window all-visible
    (put window :layout-hidden nil)
    (put window :layout-box nil))
  (def windows (filter |(not ($ :float)) all-visible))
  (when (empty? windows) (break))
  (def usable (output/usable-area output))
  # Per-output layout parameters, falling back to global config.
  (def gcfg (wm :config))
  (def cfg @{:outer-padding (gcfg :outer-padding)
             :inner-padding (gcfg :inner-padding)
             :main-ratio    (or (output :main-ratio) (gcfg :main-ratio))
             :nmaster       (or (output :nmaster) (gcfg :nmaster))
             :scroller-mfact    (or (output :scroller-mfact) (gcfg :scroller-mfact))
             :scroller-location (or (output :scroller-location) (gcfg :scroller-location))})

  # Get focused window for scroller layout
  (def focused-window
    (when-let [seat (first (wm :seats))]
      (seat :focused)))

  # Compute layout boxes for each tiled window
  (def tile-location (or (output :tile-location) :left))
  (def boxes
    (case layout-type
      :tile     (layout/master-stack windows usable cfg tile-location)
      :scroller (layout/scroller windows usable cfg focused-window)
      :grid     (layout/grid windows usable cfg)
      # default: tile
      (layout/master-stack windows usable cfg tile-location)))

  (each [window box] (map tuple windows boxes)
    (if (= box :hide)
      (do
        (put window :layout-hidden true)
        (:hide (window :obj)))
      (let [[box-x box-y box-w box-h] box
            [x y w h] (clamp-to-hints window box-x box-y box-w box-h)]
        (put window :layout-hidden nil)
        # Store the original layout box (before clamp) for clip in render.
        (put window :layout-box [box-x box-y box-w box-h])
        (window/set-position window x y)
        (window/propose-dimensions window w h)))))

(defn wm/manage []
  (update wm :render-order |(->> $ (filter (fn [window] (not (window :closed))))))

  (update wm :outputs |(keep output/manage-start $))
  (update wm :windows |(keep window/manage-start $))
  (update wm :seats |(keep seat/manage-start $))

  # Protect the core manage logic so that manage-finish is always called.
  # If any step throws (e.g. nil arithmetic on a half-initialized XWayland window),
  # we log the error but still complete the manage cycle — otherwise the compositor
  # stops sending manage-start events and all keybindings become unresponsive.
  (def [ok err] (protect (do
    (each output (wm :outputs) (output/manage output))
    (each window (wm :windows) (window/manage window))
    (each seat (wm :seats) (seat/manage seat))

    (each output (wm :outputs) (wm/layout output))
    (wm/show-hide))))
  (unless ok (eprint "wm/manage error: " err))

  (each output (wm :outputs) (output/manage-finish output))
  (each window (wm :windows) (window/manage-finish window))
  (each seat (wm :seats) (seat/manage-finish seat))

  (:manage-finish (registry "river_window_manager_v1")))

(defn wm/render []
  (def [ok err] (protect (do
    (each window (wm :windows) (window/render window))
    (each seat (wm :seats) (seat/render seat)))))
  (unless ok (eprint "wm/render error: " err))
  (:render-finish (registry "river_window_manager_v1")))

(defn wm/handle-event [event]
  (match event
    [:unavailable] (do
                     (print "another window manager is already running")
                     (os/exit 1))
    [:finished] (os/exit 0)
    [:manage-start] (wm/manage)
    [:render-start] (wm/render)
    [:output obj] (array/push (wm :outputs) (output/create obj))
    [:seat obj] (array/push (wm :seats) (seat/create obj))
    [:window obj] (array/insert (wm :windows) 0 (window/create obj))))

(defn registry/handle-event [event]
  (match event
    [:global name interface version]
    (when-let [required-version (get required-interfaces interface)]
      (when (< version required-version)
        (errorf "wayland compositor supported %s version too old (need %d, got %d)"
                interface required-version version))
      (put registry interface (:bind (registry :obj) name interface required-version)))))

(defn action/target [seat dir]
  (when-let [window (seat :focused)
             output (window/tag-output window)
             visible (output/visible output (wm :windows))
             i (assert (index-of window visible))]
    (case dir
      :next (get visible (+ i 1) (first visible))
      :prev (get visible (- i 1) (last visible))
      (error "invalid dir"))))

(defn action/spawn [command]
  (fn [seat binding]
    (ev/spawn
      (os/proc-wait (os/spawn command :p)))))

(defn action/close []
  (fn [seat binding]
    (if-let [window (seat :focused)]
      (:close (window :obj)))))

(defn action/zoom []
  (fn [seat binding]
    (when-let [focused (seat :focused)
               output (window/tag-output focused)
               visible (filter |(not ($ :float)) (output/visible output (wm :windows)))]
      (when (and (not (focused :float)) (not (empty? visible)))
        (def target (if (= focused (first visible)) (get visible 1) focused))
        (when-let [i (index-of target (wm :windows))]
          (array/remove (wm :windows) i)
          (array/insert (wm :windows) 0 target)
          (seat/focus seat (first (wm :windows))))))))

(defn action/focus [dir]
  (fn [seat binding]
    (seat/focus seat (action/target seat dir))))

(defn action/focus-output [dir]
  "Cycle focus to next/prev output. dir: :next :prev"
  (fn [seat binding]
    (when-let [focused (seat :focused-output)
               i (assert (index-of focused (wm :outputs)))]
      (def target (case dir
                    :next (or (get (wm :outputs) (+ i 1))
                              (first (wm :outputs)))
                    :prev (or (get (wm :outputs) (- i 1))
                              (last (wm :outputs)))))
      (when target
        (seat/focus-output seat target)
        (seat/focus seat nil)))))

(defn action/float []
  (fn [seat binding]
    (if-let [window (seat :focused)]
      (do
        (window/set-float window (not (window :float)))
        (if (window :float)
          (do
            (put window :user-float true)
            # Restore original dimensions when returning to float
            (when (and (window :original-w) (window :original-h))
              (:propose-dimensions (window :obj) (window :original-w) (window :original-h)))
            (put window :x nil)
            (put window :y nil))
          (put window :user-float nil))))))

(defn action/fullscreen []
  (fn [seat binding]
    (if-let [window (seat :focused)]
      (if (window :fullscreen)
        (do
          (window/set-fullscreen window nil)
          # Restore pre-fullscreen position and dimensions for floating windows.
          # Tiled windows don't need this — wm/layout will reposition them.
          (when (window :float)
            (when-let [x (window :pre-fullscreen-x)
                       y (window :pre-fullscreen-y)]
              (put window :x nil)
              (put window :y nil)
              (window/set-position window x y))
            (when-let [w (window :pre-fullscreen-w)
                       h (window :pre-fullscreen-h)]
              (:propose-dimensions (window :obj) w h))
            (put window :pre-fullscreen-x nil)
            (put window :pre-fullscreen-y nil)
            (put window :pre-fullscreen-w nil)
            (put window :pre-fullscreen-h nil)))
        (do
          # Save current geometry before going fullscreen.
          (when (window :float)
            (put window :pre-fullscreen-x (window :x))
            (put window :pre-fullscreen-y (window :y))
            (put window :pre-fullscreen-w (window :w))
            (put window :pre-fullscreen-h (window :h)))
          (window/set-fullscreen window (window/tag-output window)))))))

(defn action/retile []
  "Reset all user-floated windows on the focused output back to tiled.
   Does not affect programmatically floated windows (popups, fixed-size)."
  (fn [seat binding]
    (when-let [output (seat :focused-output)]
      (each window (output/visible output (wm :windows))
        (when (window :user-float)
          (window/set-float window false)
          (put window :user-float nil)
          (put window :x nil)
          (put window :y nil))))))

(defn action/set-tag [tag]
  (fn [seat binding]
    (if-let [window (seat :focused)]
      (put window :tag tag))))

(defn fallback-tags [outputs]
  (for tag 1 10
    (unless (find |(($ :tags) tag) outputs)
      (when-let [output (find |(empty? ($ :tags)) outputs)]
        (put (output :tags) tag true)))))

(defn action/focus-tag [tag]
  (fn [seat binding]
    (when-let [output (seat :focused-output)]
      (each o (wm :outputs) (put (o :tags) tag nil))
      (put output :tags @{tag true})
      (fallback-tags (wm :outputs)))))

(defn action/toggle-tag [tag]
  (fn [seat binding]
    (when-let [output (seat :focused-output)]
      (if ((output :tags) tag)
        (put (output :tags) tag nil)
        (do
          (each o (wm :outputs) (put (o :tags) tag nil))
          (put (output :tags) tag true)))
      (fallback-tags (wm :outputs)))))

(defn action/focus-all-tags []
  (fn [seat binding]
    (when-let [output (seat :focused-output)]
      (each o (wm :outputs) (put o :tags @{}))
      (put output :tags (table ;(mapcat |[$ true] (range 1 10))))
      (fallback-tags (wm :outputs)))))

(defn action/pointer-move []
  (fn [seat binding]
    (when-let [window (seat :pointer-target)]
      (seat/pointer-move seat window))))

(defn action/pointer-resize []
  (fn [seat binding]
    (when-let [window (seat :pointer-target)]
      (seat/pointer-resize seat window {:bottom true :left true}))))

(defn action/passthrough []
  (fn [seat binding]
    (put binding :passthrough (not (binding :passthrough)))
    (def request (if (binding :passthrough) :disable :enable))
    (each other (seat :xkb-bindings)
      (unless (= other binding)
        (request (other :obj))))
    (each other (seat :pointer-bindings)
      (unless (= other binding)
        (request (other :obj))))))

# ============================================================================
# Additional features
# ============================================================================
# --- Pluggable layout actions ---

(defn action/set-layout
  "Switch layout on focused output. type: :tile :scroller :grid"
  [layout-type]
  (fn [seat binding]
    (when-let [output (seat :focused-output)]
      (def cur (or (output :layout) :tile))
      (put output :prev-layout cur)
      (put output :layout layout-type))))

(defn action/set-tile-location
  "Set master-stack direction on focused output. location: :left :right :top :bottom"
  [location]
  (fn [seat binding]
    (when-let [output (seat :focused-output)]
      (put output :tile-location location))))

(defn action/switch-to-previous-layout []
  (fn [seat binding]
    (when-let [output (seat :focused-output)]
      (def prev (or (output :prev-layout) :tile))
      (def cur (or (output :layout) :tile))
      (put output :prev-layout cur)
      (put output :layout prev))))


# --- Additional actions ---

(defn action/swap [dir]
  "Swap focused window with next/prev tiled window."
  (fn [seat binding]
    (when-let [window (seat :focused)
               output (window/tag-output window)
               visible (filter |(not ($ :float)) (output/visible output (wm :windows)))
               i (index-of window visible)]
      (def ti (case dir
                :next (if (< (+ i 1) (length visible)) (+ i 1) 0)
                :prev (if (> i 0) (- i 1) (- (length visible) 1))))
      (def target (get visible ti))
      (when (and target (not= target window))
        (def wi (assert (index-of window (wm :windows))))
        (def tii (assert (index-of target (wm :windows))))
        (put (wm :windows) wi target)
        (put (wm :windows) tii window)))))

(defn action/send-to-output [dir]
  "Send focused window to next/prev output."
  (fn [seat binding]
    (when-let [window (seat :focused)
               output (window/tag-output window)
               i (index-of output (wm :outputs))]
      (def target (case dir
                    :next (or (get (wm :outputs) (+ i 1)) (first (wm :outputs)))
                    :prev (or (get (wm :outputs) (- i 1)) (last (wm :outputs)))))
      (unless (= target output)
        (put window :tag (or (min-of (keys (target :tags))) 1))))))


(defn action/sticky []
  "Toggle sticky: window visible on all tags."
  (fn [seat binding]
    (when-let [window (seat :focused)]
      (put window :sticky (not (window :sticky))))))

(defn action/set-main-ratio [delta]
  "Adjust main-ratio on focused output by delta."
  (fn [seat binding]
    (when-let [output (seat :focused-output)]
      (def cur (or (output :main-ratio) ((wm :config) :main-ratio)))
      (put output :main-ratio (max 0.1 (min 0.9 (+ cur delta)))))))

(defn action/set-nmaster [delta]
  "Adjust nmaster count on focused output."
  (fn [seat binding]
    (when-let [output (seat :focused-output)]
      (def cur (or (output :nmaster) ((wm :config) :nmaster) 1))
      (put output :nmaster (max 1 (+ cur delta))))))

(defn action/float-move [dx dy]
  "Move focused floating window by dx/dy pixels, clamped to output usable area."
  (fn [seat binding]
    (when-let [window (seat :focused)]
      (when (and (window :float) (window :x) (window :y) (window :w) (window :h))
        (def output (or (window/tag-output window) (seat :focused-output)))
        (when output
          (def usable (output/usable-area output))
          (def gap ((wm :config) :outer-padding))
          (def bw2 (* 2 ((wm :config) :border-width)))
          (def min-x (+ (usable :x) (- (+ (window :w) bw2)) gap))
          (def max-x (- (+ (usable :x) (usable :w)) gap))
          (def min-y (+ (usable :y) (- (+ (window :h) bw2)) gap))
          (def max-y (- (+ (usable :y) (usable :h)) gap))
          (def new-x (max min-x (min (+ (window :x) dx) max-x)))
          (def new-y (max min-y (min (+ (window :y) dy) max-y)))
          (window/set-position window new-x new-y))))))

(defn action/float-resize [dw dh]
  "Resize focused floating window, always centered in usable area.
   Size is clamped to client hints and usable area; once any edge
   reaches the boundary, it stops growing."
  (fn [seat binding]
    (when-let [window (seat :focused)]
      (when (and (window :float) (window :w) (window :h) (window :x) (window :y))
        (def output (or (window/tag-output window) (seat :focused-output)))
        (when output
          (def usable (output/usable-area output))
          (def bw2 (* 2 ((wm :config) :border-width)))
          (def old-tw (+ (window :w) bw2))
          (def old-th (+ (window :h) bw2))
          # Client hints (content → layout space)
          (def hint-min-w (if (and (window :min-w) (> (window :min-w) 0))
                            (+ (window :min-w) bw2) 1))
          (def hint-min-h (if (and (window :min-h) (> (window :min-h) 0))
                            (+ (window :min-h) bw2) 1))
          (def hint-max-w (if (and (window :max-w) (> (window :max-w) 0))
                            (+ (window :max-w) bw2) (usable :w)))
          (def hint-max-h (if (and (window :max-h) (> (window :max-h) 0))
                            (+ (window :max-h) bw2) (usable :h)))
          # Clamp to hints and usable area
          (def new-w (max hint-min-w (min (+ old-tw dw) (min hint-max-w (usable :w)))))
          (def new-h (max hint-min-h (min (+ old-th dh) (min hint-max-h (usable :h)))))
          # Center in usable area
          (def new-x (+ (usable :x) (div (- (usable :w) new-w) 2)))
          (def new-y (+ (usable :y) (div (- (usable :h) new-h) 2)))
          (window/set-position window new-x new-y)
          (window/propose-dimensions window new-w new-h))))))

(defn action/float-snap [edge]
  "Snap floating window to output edge."
  (fn [seat binding]
    (when-let [window (seat :focused)
               output (window/tag-output window)]
      (when (and (window :float) (window :x) (window :y) (window :w) (window :h))
        (def usable (output/usable-area output))
        (def bw2 (* 2 ((wm :config) :border-width)))
        (case edge
          :left   (window/set-position window (usable :x) (window :y))
          :right  (window/set-position window
                                       (- (+ (usable :x) (usable :w)) (window :w) bw2)
                                       (window :y))
          :top    (window/set-position window (window :x) (usable :y))
          :bottom (window/set-position window
                                       (window :x)
                                       (- (+ (usable :y) (usable :h)) (window :h) bw2)))))))


# Only main is marshaled when building a standalone executable,
# so we must capture the REPL environment outside of main.
(def repl-env (curenv))
(defn repl-server-create []
  (def path (string/format "%s/rijan-%s"
                           (assert (os/getenv "XDG_RUNTIME_DIR"))
                           (assert (os/getenv "WAYLAND_DISPLAY"))))
  (protect (os/rm path))
  (netrepl/server :unix path repl-env))

(defn main [& args]
  (def display (wayland/connect interfaces))

  # Avoid passing WAYLAND_DEBUG on to our children.
  # It only matters if it's set when the display is created.
  (os/setenv "WAYLAND_DEBUG" nil)

  (def config-dir (or (os/getenv "XDG_CONFIG_HOME")
                      (string (os/getenv "HOME") "/.config")))
  (def init-path (get 1 args (string config-dir "/rijan/init.janet")))
  (when-let [init (file/open init-path :r)]
    (dofile init :env repl-env)
    (file/close init))

  (put registry :obj (:get-registry display))
  (:set-handler (registry :obj) registry/handle-event)
  (:roundtrip display)
  (eachk i required-interfaces
    (unless (get registry i)
      (errorf "wayland compositor does not support %s" i)))

  (:set-handler (registry "river_window_manager_v1") wm/handle-event)

  # Do a roundtrip to give the compositor the chance to send the
  # :unavailable event before creating the repl server and potentially
  # overwriting the repl socket of an already running rijan instance.
  (:roundtrip display)

  (def repl-server (repl-server-create))

  (defer (:close repl-server)
    (forever (:dispatch display))))
