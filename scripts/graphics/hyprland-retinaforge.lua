-- Hardware pin for MacBookPro11,3 Hyprland (Iris Pro lid).
--
-- Omarchy 4.0 (Hyprland 0.56 Lua): load this LAST in
-- ~/.config/hypr/hyprland.lua so it wins over Omarchy's
-- preferred/auto monitor rule:
--
--   dofile("/usr/local/share/retinaforge/hyprland-retinaforge.lua")
--
-- Do not load hyprland-intel.conf / hyprland-intel.lua on Omarchy —
-- that CachyOS daily file fights their Quickshell rice.
--
-- CachyOS daily still uses the hyprlang twin
-- hyprland-retinaforge.conf (Hyprland 0.56 still loads .conf).
--
-- Do not point AQ_DRM_DEVICES at /dev/dri/by-path (colons). Do not add
-- the GT 750M card here — HDMI/TB stay on that GPU as a separate
-- experiment.

hl.env("AQ_DRM_DEVICES", "/dev/dri/intel-igpu")
hl.env("AQ_NO_ATOMIC", "1")
hl.env("WLR_DRM_DEVICES", "/dev/dri/intel-igpu")
hl.env("WLR_DRM_NO_ATOMIC", "1")
hl.env("XCURSOR_SIZE", "36")
hl.env("GDK_SCALE", "2")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")

hl.monitor({
	output = "eDP-2",
	mode = "2880x1800@59.99",
	position = "0x0",
	scale = 2,
})
hl.monitor({
	output = "",
	mode = "preferred",
	position = "auto",
	scale = 2,
})

-- hid_apple swap_opt_cmd=0 makes Command = Super. Do not use xkb
-- applealu_iso+mac here — that combo fights the hid map.
hl.config({
	input = {
		kb_layout = "nl",
		kb_model = "pc105",
		follow_mouse = 1,
		touchpad = {
			natural_scroll = true,
			tap_to_click = true,
			clickfinger_behavior = true,
			disable_while_typing = true,
		},
	},
	misc = {
		disable_hyprland_logo = true,
		force_default_wallpaper = 0,
		mouse_move_enables_dpms = true,
		key_press_enables_dpms = true,
	},
	decoration = {
		blur = { enabled = false },
	},
})

hl.gesture({
	fingers = 3,
	direction = "horizontal",
	action = "workspace",
})

-- gmux_backlight (brightnessctl's default device often misses this chip).
hl.bind(
	"XF86MonBrightnessUp",
	hl.dsp.exec_cmd("/usr/local/bin/retinaforge-brightness +5%"),
	{ locked = true, repeating = true }
)
hl.bind(
	"XF86MonBrightnessDown",
	hl.dsp.exec_cmd("/usr/local/bin/retinaforge-brightness 5%-"),
	{ locked = true, repeating = true }
)
