const std = @import("std");
const glfw = @import("mach-glfw");
const gl = @import("gl");
const zigimg = @import("zigimg");
const zm = @import("zm");

const glfw_log = std.log.scoped(.glfw);
const gl_log = std.log.scoped(.gl);
const log = std.log;

const core = @import("core.zig");
const scene = @import("scene.zig");

pub const InputHandler = struct {
    cam: *scene.Camera,
    scene: Scene = .no_skybox_textured,

    pub const Scene = union(enum) {
        skybox,
        no_skybox_raw,
        no_skybox_textured,
        no_skybox_textured_spotlight,
        no_skybox_textured_multilight,
    };

    pub fn init(cam: *scene.Camera) InputHandler {
        return .{ .cam = cam };
    }

    pub fn mouseCallback(self: *InputHandler, x: f64, y: f64) void {
        self.cam.mouseCallback(x, y);
    }

    pub fn keyCallback(
        self: *InputHandler,
        window: glfw.Window,
        key: glfw.Key,
        scancode: i32,
        action: glfw.Action,
        mods: glfw.Mods,
    ) void {
        _ = scancode;
        _ = mods;

        if (action == .press) {
            switch (key) {
                .q => window.setShouldClose(true),
                .one => {
                    self.scene = .skybox;
                },
                .two => {
                    self.scene = .no_skybox_raw;
                },
                .three => {
                    self.scene = .no_skybox_textured;
                },
                .four => {
                    self.scene = .no_skybox_textured_spotlight;
                },
                .five => {
                    self.scene = .no_skybox_textured_multilight;
                },
                else => {},
            }
        }
        // TODO: It would be very nice to be able to hook any functions with a given key
        // + action, so that we can do anything from user code without touching the
        // input handler. For this we would need a Map of .{keycode, action} -> comptime fn or something like that.
    }

    pub fn consume(self: *InputHandler, window: glfw.Window) void {
        if (window.getKey(.w) == .press) {
            self.cam.moveFwd();
        } else if (window.getKey(.s) == .press) {
            self.cam.moveBck();
        } else if (window.getKey(.a) == .press) {
            self.cam.moveLeft();
        } else if (window.getKey(.d) == .press) {
            self.cam.moveRight();
        }
    }
};
