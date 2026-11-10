--
-- OBS Zoom to Mouse (Modified for Dynamic Aspect Ratio)
-- An OBS lua script to zoom a display-capture source to focus on the mouse.
--

local obs = obslua
local ffi = require("ffi")
local VERSION = "1.1-AR"
local CROP_FILTER_NAME = "obs-zoom-to-mouse-crop"

local source_name = ""
local source = nil
local sceneitem = nil
local sceneitem_info_orig = nil
local sceneitem_crop_orig = nil
local sceneitem_info = nil
local sceneitem_crop = nil
local crop_filter = nil
local crop_filter_temp = nil
local crop_filter_settings = nil
local crop_filter_info_orig = { x = 0, y = 0, w = 0, h = 0 }
local crop_filter_info = { x = 0, y = 0, w = 0, h = 0 }
local monitor_info = nil
local zoom_info = {
    source_size = { width = 0, height = 0 },
    source_crop = { x = 0, y = 0, w = 0, h = 0 },
    source_crop_filter = { x = 0, y = 0, w = 0, h = 0 },
    zoom_to = 2
}
local zoom_time = 0
local zoom_target = nil
local locked_center = nil
local locked_last_pos = nil
local hotkey_zoom_id = nil
local hotkey_follow_id = nil
local is_timer_running = false

local win_point = nil
local x11_display = nil
local x11_root = nil
local x11_mouse = nil
local osx_lib = nil
local osx_nsevent = nil
local osx_mouse_location = nil

local use_auto_follow_mouse = true
local use_follow_outside_bounds = false
local is_following_mouse = false
local follow_speed = 0.1
local follow_border = 0
local follow_safezone_sensitivity = 10
local use_follow_auto_lock = false
local zoom_value = 2
local zoom_speed = 0.1
local zoom_aspect_ratio = 1.777
local allow_all_sources = false
local use_monitor_override = false
local monitor_override_x = 0
local monitor_override_y = 0
local monitor_override_w = 0
local monitor_override_h = 0
local monitor_override_sx = 0
local monitor_override_sy = 0
local monitor_override_dw = 0
local monitor_override_dh = 0
local debug_logs = false

local ZoomState = {
    None = 0,
    ZoomingIn = 1,
    ZoomingOut = 2,
    ZoomedIn = 3,
}
local zoom_state = ZoomState.None

local version = obs.obs_get_version_string()
local major = tonumber(version:match("(%d+%.%d+)")) or 0

-- Define the mouse cursor functions for each platform
if ffi.os == "Windows" then
    ffi.cdef([[
        typedef int BOOL;
        typedef struct{
            long x;
            long y;
        } POINT, *LPPOINT;
        BOOL GetCursorPos(LPPOINT);
    ]])
    win_point = ffi.new("POINT[1]")
elseif ffi.os == "Linux" then
    ffi.cdef([[
        typedef unsigned long XID;
        typedef XID Window;
        typedef void Display;
        Display* XOpenDisplay(char*);
        XID XDefaultRootWindow(Display *display);
        int XQueryPointer(Display*, Window, Window*, Window*, int*, int*, int*, int*, unsigned int*);
        int XCloseDisplay(Display*);
    ]])

    x11_lib = ffi.load("X11.so.6")
    x11_display = x11_lib.XOpenDisplay(nil)
    if x11_display ~= nil then
        x11_root = x11_lib.XDefaultRootWindow(x11_display)
        x11_mouse = {
            root_win = ffi.new("Window[1]"),
            child_win = ffi.new("Window[1]"),
            root_x = ffi.new("int[1]"),
            root_y = ffi.new("int[1]"),
            win_x = ffi.new("int[1]"),
            win_y = ffi.new("int[1]"),
            mask = ffi.new("unsigned int[1]")
        }
    end
elseif ffi.os == "OSX" then
    ffi.cdef([[
        typedef struct {
            double x;
            double y;
        } CGPoint;
        typedef void* SEL;
        typedef void* id;
        typedef void* Method;

        SEL sel_registerName(const char *str);
        id objc_getClass(const char*);
        Method class_getClassMethod(id cls, SEL name);
        void* method_getImplementation(Method);
        int access(const char *path, int amode);
    ]])

    osx_lib = ffi.load("libobjc")
    if osx_lib ~= nil then
        osx_nsevent = {
            class = osx_lib.objc_getClass("NSEvent"),
            sel = osx_lib.sel_registerName("mouseLocation")
        }
        local method = osx_lib.class_getClassMethod(osx_nsevent.class, osx_nsevent.sel)
        if method ~= nil then
            local imp = osx_lib.method_getImplementation(method)
            osx_mouse_location = ffi.cast("CGPoint(*)(void*, void*)", imp)
        end
    end
end

function get_mouse_pos()
    local mouse = { x = 0, y = 0 }
    if ffi.os == "Windows" then
        if win_point and ffi.C.GetCursorPos(win_point) ~= 0 then
            mouse.x = win_point[0].x
            mouse.y = win_point[0].y
        end
    elseif ffi.os == "Linux" then
        if x11_lib ~= nil and x11_display ~= nil and x11_root ~= nil and x11_mouse ~= nil then
            if x11_lib.XQueryPointer(x11_display, x11_root, x11_mouse.root_win, x11_mouse.child_win, x11_mouse.root_x, x11_mouse.root_y, x11_mouse.win_x, x11_mouse.win_y, x11_mouse.mask) ~= 0 then
                mouse.x = tonumber(x11_mouse.win_x[0])
                mouse.y = tonumber(x11_mouse.win_y[0])
            end
        end
    elseif ffi.os == "OSX" then
        if osx_lib ~= nil and osx_nsevent ~= nil and osx_mouse_location ~= nil then
            local point = osx_mouse_location(osx_nsevent.class, osx_nsevent.sel)
            mouse.x = point.x
            if monitor_info ~= nil then
                if monitor_info.display_height > 0 then
                    mouse.y = monitor_info.display_height - point.y
                else
                    mouse.y = monitor_info.height - point.y
                end
            end
        end
    end
    return mouse
end

function get_dc_info()
    if ffi.os == "Windows" then
        return { source_id = "monitor_capture", prop_id = "monitor_id", prop_type = "string" }
    elseif ffi.os == "Linux" then
        return { source_id = "xshm_input", prop_id = "screen", prop_type = "int" }
    elseif ffi.os == "OSX" then
        if major > 29.0 then
            return { source_id = "screen_capture", prop_id = "display_uuid", prop_type = "string" }
        else
            return { source_id = "display_capture", prop_id = "display", prop_type = "int" }
        end
    end
    return nil
end

function log(msg)
    if debug_logs then obs.script_log(obs.OBS_LOG_INFO, msg) end
end

function format_table(tbl, indent)
    if not indent then indent = 0 end
    local str = "{\n"
    for key, value in pairs(tbl) do
        local tabs = string.rep("  ", indent + 1)
        if type(value) == "table" then
            str = str .. tabs .. key .. " = " .. format_table(value, indent + 1) .. ",\n"
        else
            str = str .. tabs .. key .. " = " .. tostring(value) .. ",\n"
        end
    end
    str = str .. string.rep("  ", indent) .. "}"
    return str
end

function lerp(v0, v1, t) return v0 * (1 - t) + v1 * t end

function ease_in_out(t)
    t = t * 2
    if t < 1 then return 0.5 * t * t * t
    else
        t = t - 2
        return 0.5 * (t * t * t + 2)
    end
end

function clamp(min, max, value) return math.max(min, math.min(max, value)) end

function get_monitor_info(source)
    local info = nil
    if is_display_capture(source) and not use_monitor_override then
        local dc_info = get_dc_info()
        if dc_info ~= nil then
            local props = obs.obs_source_properties(source)
            if props ~= nil then
                local monitor_id_prop = obs.obs_properties_get(props, dc_info.prop_id)
                if monitor_id_prop then
                    local found = nil
                    local settings = obs.obs_source_get_settings(source)
                    if settings ~= nil then
                        local to_match
                        if dc_info.prop_type == "string" then to_match = obs.obs_data_get_string(settings, dc_info.prop_id)
                        elseif dc_info.prop_type == "int" then to_match = obs.obs_data_get_int(settings, dc_info.prop_id) end
                        local item_count = obs.obs_property_list_item_count(monitor_id_prop);
                        for i = 0, item_count do
                            local name = obs.obs_property_list_item_name(monitor_id_prop, i)
                            local value
                            if dc_info.prop_type == "string" then value = obs.obs_property_list_item_string(monitor_id_prop, i)
                            elseif dc_info.prop_type == "int" then value = obs.obs_property_list_item_int(monitor_id_prop, i) end
                            if value == to_match then found = name break end
                        end
                        obs.obs_data_release(settings)
                    end
                    if found then
                        local x, y = found:match("(-?%d+),(-?%d+)")
                        local width, height = found:match("(%d+)x(%d+)")
                        info = { x = tonumber(x, 10), y = tonumber(y, 10), width = tonumber(width, 10), height = tonumber(height, 10), scale_x = 1, scale_y = 1, display_width = tonumber(width, 10), display_height = tonumber(height, 10) }
                        if info.width == 0 and info.height == 0 then info = nil end
                    end
                end
                obs.obs_properties_destroy(props)
            end
        end
    end
    if use_monitor_override then
        info = { x = monitor_override_x, y = monitor_override_y, width = monitor_override_w, height = monitor_override_h, scale_x = monitor_override_sx, scale_y = monitor_override_sy, display_width = monitor_override_dw, display_height = monitor_override_dh }
    end
    return info
end

function is_display_capture(source_to_check)
    if source_to_check ~= nil then
        local dc_info = get_dc_info()
        if dc_info ~= nil then
            if allow_all_sources then return true
            else
                local source_type = obs.obs_source_get_id(source_to_check)
                if source_type == dc_info.source_id then return true end
            end
        end
    end
    return false
end

function release_sceneitem()
    if is_timer_running then obs.timer_remove(on_timer) is_timer_running = false end
    zoom_state = ZoomState.None
    if sceneitem ~= nil then
        if crop_filter ~= nil and source ~= nil then obs.obs_source_filter_remove(source, crop_filter) obs.obs_source_release(crop_filter) crop_filter = nil end
        if crop_filter_temp ~= nil and source ~= nil then obs.obs_source_filter_remove(source, crop_filter_temp) obs.obs_source_release(crop_filter_temp) crop_filter_temp = nil end
        if crop_filter_settings ~= nil then obs.obs_data_release(crop_filter_settings) crop_filter_settings = nil end
        obs.obs_sceneitem_release(sceneitem)
        sceneitem = nil
    end
    if source ~= nil then obs.obs_source_release(source) source = nil end
end

function refresh_sceneitem(find_newest)
    local source_raw = { width = 0, height = 0 }
    if find_newest then
        release_sceneitem()
        if source_name == "obs-zoom-to-mouse-none" then return end
        source = obs.obs_get_source_by_name(source_name)
        if source ~= nil then
            source_raw.width = obs.obs_source_get_width(source)
            source_raw.height = obs.obs_source_get_height(source)
            local scene_source = obs.obs_frontend_get_current_scene()
            if scene_source ~= nil then
                local current = obs.obs_scene_from_source(scene_source)
                sceneitem = obs.obs_scene_find_source(current, source_name)
                if sceneitem then obs.obs_sceneitem_addref(sceneitem) end
                obs.obs_source_release(scene_source)
            end
        end
    end

    if sceneitem ~= nil then
        sceneitem_info_orig = obs.obs_transform_info()
        obs.obs_sceneitem_get_info2(sceneitem, sceneitem_info_orig)
        sceneitem_crop_orig = obs.obs_sceneitem_crop()
        obs.obs_sceneitem_get_crop(sceneitem, sceneitem_crop_orig)

        local source_width = obs.obs_source_get_base_width(source)
        local source_height = obs.obs_source_get_base_height(source)
        if source_width == 0 then source_width = source_raw.width end
        if source_height == 0 then source_height = source_raw.height end

        zoom_info.source_size = { width = source_width, height = source_height }
        zoom_info.source_crop_filter = { x = 0, y = 0, w = source_width, h = source_height }

        crop_filter_info_orig = { x = 0, y = 0, w = source_width, h = source_height }
        crop_filter_info = { x = 0, y = 0, w = source_width, h = source_height }

        crop_filter = obs.obs_source_get_filter_by_name(source, CROP_FILTER_NAME)
        if crop_filter == nil then
            crop_filter_settings = obs.obs_data_create()
            obs.obs_data_set_bool(crop_filter_settings, "relative", false)
            crop_filter = obs.obs_source_create_private("crop_filter", CROP_FILTER_NAME, crop_filter_settings)
            obs.obs_source_filter_add(source, crop_filter)
        else
            crop_filter_settings = obs.obs_source_get_settings(crop_filter)
        end
        obs.obs_source_filter_set_order(source, crop_filter, obs.OBS_ORDER_MOVE_BOTTOM)
        set_crop_settings(crop_filter_info_orig)
    end
end

---
-- Modified get_target_position to handle Dynamic Aspect Ratio
---
function get_target_position(zoom)
    local mouse = get_mouse_pos()
    if monitor_info then
        mouse.x = mouse.x - monitor_info.x
        mouse.y = mouse.y - monitor_info.y
    end
    mouse.x = mouse.x - zoom.source_crop_filter.x
    mouse.y = mouse.y - zoom.source_crop_filter.y

    if monitor_info and monitor_info.scale_x and monitor_info.scale_y then
        mouse.x = mouse.x * monitor_info.scale_x
        mouse.y = mouse.y * monitor_info.scale_y
    end

    -- DYNAMIC ASPECT RATIO CALCULATION
    -- We derive height from zoom factor, then derive width from that height using the ratio
    local target_h = zoom.source_size.height / zoom.zoom_to
    local target_w = target_h * zoom_aspect_ratio

    local new_size = {
        width = target_w,
        height = target_h
    }

    local pos = {
        x = mouse.x - new_size.width * 0.5,
        y = mouse.y - new_size.height * 0.5
    }

    local crop = {
        x = pos.x,
        y = pos.y,
        w = new_size.width,
        h = new_size.height,
    }

    -- Keep in bounds
    crop.x = math.floor(clamp(0, (zoom.source_size.width - new_size.width), crop.x))
    crop.y = math.floor(clamp(0, (zoom.source_size.height - new_size.height), crop.y))

    return { crop = crop, raw_center = mouse, clamped_center = { x = math.floor(crop.x + crop.w * 0.5), y = math.floor(crop.y + crop.h * 0.5) } }
end

function on_toggle_follow(pressed)
    if pressed then
        is_following_mouse = not is_following_mouse
        if is_following_mouse and zoom_state == ZoomState.ZoomedIn then
            if not is_timer_running then
                is_timer_running = true
                obs.timer_add(on_timer, math.floor(obs.obs_get_frame_interval_ns() / 1000000))
            end
        end
    end
end

function on_toggle_zoom(pressed)
    if pressed then
        if zoom_state == ZoomState.ZoomedIn or zoom_state == ZoomState.None then
            if zoom_state == ZoomState.ZoomedIn then
                zoom_state = ZoomState.ZoomingOut
                zoom_time = 0
                zoom_target = { crop = crop_filter_info_orig }
                is_following_mouse = false
            else
                zoom_state = ZoomState.ZoomingIn
                zoom_info.zoom_to = zoom_value
                zoom_time = 0
                zoom_target = get_target_position(zoom_info)
            end
            if not is_timer_running then
                is_timer_running = true
                obs.timer_add(on_timer, math.floor(obs.obs_get_frame_interval_ns() / 1000000))
            end
        end
    end
end

function on_timer()
    if crop_filter_info ~= nil and zoom_target ~= nil then
        zoom_time = zoom_time + zoom_speed
        if zoom_state == ZoomState.ZoomingOut or zoom_state == ZoomState.ZoomingIn then
            if zoom_time <= 1 then
                if zoom_state == ZoomState.ZoomingIn and use_auto_follow_mouse then zoom_target = get_target_position(zoom_info) end
                crop_filter_info.x = lerp(crop_filter_info.x, zoom_target.crop.x, ease_in_out(zoom_time))
                crop_filter_info.y = lerp(crop_filter_info.y, zoom_target.crop.y, ease_in_out(zoom_time))
                crop_filter_info.w = lerp(crop_filter_info.w, zoom_target.crop.w, ease_in_out(zoom_time))
                crop_filter_info.h = lerp(crop_filter_info.h, zoom_target.crop.h, ease_in_out(zoom_time))
                set_crop_settings(crop_filter_info)
            end
        else
            if is_following_mouse then
                zoom_target = get_target_position(zoom_info)
                crop_filter_info.x = lerp(crop_filter_info.x, zoom_target.crop.x, follow_speed)
                crop_filter_info.y = lerp(crop_filter_info.y, zoom_target.crop.y, follow_speed)
                set_crop_settings(crop_filter_info)
            end
        end

        if zoom_time >= 1 then
            if zoom_state == ZoomState.ZoomingOut then zoom_state = ZoomState.None is_timer_running = false obs.timer_remove(on_timer)
            elseif zoom_state == ZoomState.ZoomingIn then
                zoom_state = ZoomState.ZoomedIn
                if use_auto_follow_mouse then is_following_mouse = true end
                if not is_following_mouse then is_timer_running = false obs.timer_remove(on_timer) end
            end
        end
    end
end

function set_crop_settings(crop)
    if crop_filter ~= nil and crop_filter_settings ~= nil then
        obs.obs_data_set_int(crop_filter_settings, "left", math.floor(crop.x))
        obs.obs_data_set_int(crop_filter_settings, "top", math.floor(crop.y))
        obs.obs_data_set_int(crop_filter_settings, "cx", math.floor(crop.w))
        obs.obs_data_set_int(crop_filter_settings, "cy", math.floor(crop.h))
        obs.obs_source_update(crop_filter, crop_filter_settings)
    end
end

function script_properties()
    local props = obs.obs_properties_create()
    local sources_list = obs.obs_properties_add_list(props, "source", "Zoom Source", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    populate_zoom_sources(sources_list)
    
    obs.obs_properties_add_float(props, "zoom_value", "Zoom Factor", 1, 10, 0.1)
    obs.obs_properties_add_float_slider(props, "zoom_speed", "Zoom Speed", 0.01, 1, 0.01)
    
    -- NEW PROPERTY: ASPECT RATIO
    local ar_prop = obs.obs_properties_add_float(props, "aspect_ratio", "Zoom Aspect Ratio (W/H)", 0.1, 5.0, 0.001)
    obs.obs_property_set_long_description(ar_prop, "Set to 1.0 for Square, 1.777 for 16:9, 1.333 for 4:3")

    obs.obs_properties_add_bool(props, "follow", "Auto follow mouse")
    obs.obs_properties_add_float_slider(props, "follow_speed", "Follow Speed", 0.01, 1, 0.01)
    obs.obs_properties_add_bool(props, "debug_logs", "Enable debug logging")
    
    return props
end

function script_update(settings)
    source_name = obs.obs_data_get_string(settings, "source")
    zoom_value = obs.obs_data_get_double(settings, "zoom_value")
    zoom_speed = obs.obs_data_get_double(settings, "zoom_speed")
    zoom_aspect_ratio = obs.obs_data_get_double(settings, "aspect_ratio")
    use_auto_follow_mouse = obs.obs_data_get_bool(settings, "follow")
    follow_speed = obs.obs_data_get_double(settings, "follow_speed")
    debug_logs = obs.obs_data_get_bool(settings, "debug_logs")
    refresh_sceneitem(true)
    monitor_info = get_monitor_info(source)
end

function script_load(settings)
    hotkey_zoom_id = obs.obs_hotkey_register_frontend("toggle_zoom_hotkey", "Toggle zoom to mouse", on_toggle_zoom)
    hotkey_follow_id = obs.obs_hotkey_register_frontend("toggle_follow_hotkey", "Toggle follow mouse during zoom", on_toggle_follow)
    zoom_aspect_ratio = obs.obs_data_get_double(settings, "aspect_ratio")
    obs.obs_frontend_add_event_callback(function(event)
        if event == obs.OBS_FRONTEND_EVENT_SCENE_CHANGED then refresh_sceneitem(true) end
    end)
end

function script_defaults(settings)
    obs.obs_data_set_default_double(settings, "zoom_value", 2.0)
    obs.obs_data_set_default_double(settings, "zoom_speed", 0.06)
    obs.obs_data_set_default_double(settings, "aspect_ratio", 1.777)
    obs.obs_data_set_default_bool(settings, "follow", true)
    obs.obs_data_set_default_double(settings, "follow_speed", 0.25)
end

function populate_zoom_sources(list)
    obs.obs_property_list_clear(list)
    local sources = obs.obs_enum_sources()
    if sources ~= nil then
        local dc_info = get_dc_info()
        obs.obs_property_list_add_string(list, "<None>", "obs-zoom-to-mouse-none")
        for _, s in ipairs(sources) do
            local name = obs.obs_source_get_name(s)
            obs.obs_property_list_add_string(list, name, name)
        end
        obs.source_list_release(sources)
    end
end