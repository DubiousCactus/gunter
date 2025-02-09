const std = @import("std");
const glfw = @import("mach-glfw");
const gl = @import("gl");
const zigimg = @import("zigimg");
const zm = @import("zm");

const glfw_log = std.log.scoped(.glfw);
const gl_log = std.log.scoped(.gl);
const log = std.log;

const core = @import("core.zig");

pub const Camera = struct {
    translation: zm.Vec3f,
    pitch_yaw_speed: f32 = 0.1,
    yaw: f32 = -90.0,
    pitch: f32 = 0.0,
    last_mouse_x: f64 = 0,
    last_mouse_y: f64 = 0,
    first_mouse_enter: bool = true,
    up: zm.Vec3f = -zm.vec.up(f32),
    front: zm.Vec3f = zm.vec.forward(f32),
    strife_speed: f32 = 25,
    ticker: *core.Ticker,

    pub fn init(ticker: *core.Ticker, translation: ?zm.Vec3f) Camera {
        return Camera{
            .ticker = ticker,
            .translation = translation orelse zm.vec.zero(3, f32),
        };
    }

    pub fn mouseCallback(self: *Camera, x: f64, y: f64) void {
        if (self.first_mouse_enter) {
            self.last_mouse_x = x;
            self.last_mouse_y = y;
            self.first_mouse_enter = false;
        }
        self.yaw = std.math.clamp(
            self.yaw + self.pitch_yaw_speed * @as(f32, @floatCast(self.last_mouse_x - x)),
            -180.0,
            180.0,
        );
        self.pitch = std.math.clamp(
            self.pitch + self.pitch_yaw_speed * @as(f32, @floatCast(y - self.last_mouse_y)),
            -180.0,
            180.0,
        );
        self.last_mouse_x = x;
        self.last_mouse_y = y;
    }

    pub fn moveFwd(self: *Camera) void {
        self.translation += zm.vec.scale(
            self.front,
            self.strife_speed * @as(f32, @floatCast(
                self.ticker.deltaSeconds(),
            )),
        );
    }

    pub fn moveBck(self: *Camera) void {
        self.translation -= zm.vec.scale(
            self.front,
            self.strife_speed * @as(f32, @floatCast(
                self.ticker.deltaSeconds(),
            )),
        );
    }

    pub fn moveLeft(self: *Camera) void {
        self.translation -= zm.vec.scale(
            zm.vec.normalize(zm.vec.cross(self.front, self.up)),
            self.strife_speed * @as(f32, @floatCast(
                self.ticker.deltaSeconds(),
            )),
        );
    }

    pub fn moveRight(self: *Camera) void {
        self.translation += zm.vec.scale(
            zm.vec.normalize(zm.vec.cross(self.front, self.up)),
            self.strife_speed * @as(f32, @floatCast(
                self.ticker.deltaSeconds(),
            )),
        );
    }

    pub fn getViewMat(self: *Camera) zm.Mat4f {
        // This is basic trigonometry, but it's also best to look at it as a unit vector
        // traveling around the unit circle. Except we consider 1 unit circle for the
        // (x,z) plane controlled by the yaw angle, and 2 for the (x, y) & (y, z) planes
        // controlled by the roll angle. Hypothenus is 1 since it's the unit vector of the
        // unit circle.
        // (x, z) plane: camera_front.x = cos(yaw_angle) * hypothenus
        // (x, y) plane: camera_front.x = cos(pitch_angle) * hypothenus
        // Combined: camera_front.x = cos(yaw) * cos(pitch).
        self.front = zm.vec.normalize(zm.Vec3f{
            std.math.cos(std.math.degreesToRadians(self.yaw)) * std.math.cos(std.math.degreesToRadians(self.pitch)),
            std.math.sin(std.math.degreesToRadians(self.pitch)),
            std.math.sin(std.math.degreesToRadians(self.yaw)) * std.math.cos(std.math.degreesToRadians(self.pitch)),
        });

        return zm.Mat4f.lookAt(self.translation, self.translation + self.front, self.up);
    }

    pub fn getSkyboxViewMat(self: *Camera) zm.Mat4f {
        // const view_mat = self.getViewMat();
        // return view_mat.removeTranslation();
        const translation = self.translation;
        self.translation = zm.vec.zero(3, f16);
        self.up = -self.up;
        const view_mat = self.getViewMat();
        self.translation = translation;
        self.up = -self.up;
        return view_mat;
    }
};

pub const InputHandler = struct {
    cam: *Camera,
    scene: Scene = .no_skybox_textured,

    pub const Scene = union(enum) {
        skybox,
        no_skybox_raw,
        no_skybox_textured,
    };

    pub fn init(cam: *Camera) InputHandler {
        return .{ .cam = cam };
    }

    pub fn mouseCallback(self: *InputHandler, x: f64, y: f64) void {
        self.cam.mouseCallback(x, y);
    }

    pub fn keyCallback(self: *InputHandler, window: glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: glfw.Mods) void {
        _ = scancode;
        _ = mods;

        if (action == .repeat) {
            switch (key) {
                .w => self.cam.moveFwd(),
                .s => self.cam.moveBck(),
                .a => self.cam.moveLeft(),
                .d => self.cam.moveRight(),
                else => {},
            }
        } else if (action == .press) {
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
                else => {},
            }
        }
        // TODO: It would be very nice to be able to hook any functions with a given key
        // + action, so that we can do anything from user code without touching the
        // input handler. For this we would need a Map of .{keycode, action} -> comptime fn or something like that.
    }
};
