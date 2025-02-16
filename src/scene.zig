const std = @import("std");
const gl = @import("gl");
const zigimg = @import("zigimg");
const zm = @import("zm");

const gl_log = std.log.scoped(.gl);
const log = std.log;

const core = @import("core.zig");
const texture = @import("texture.zig");

pub const Camera = struct {
    translation: zm.Vec3f,
    pitch_yaw_speed: f32 = 0.1,
    yaw: f32 = -90.0,
    pitch: f32 = 0.0,
    last_mouse_x: f64 = 0,
    last_mouse_y: f64 = 0,
    first_mouse_enter: bool = true,
    up: zm.Vec3f = zm.vec.up(f32),
    front: zm.Vec3f = -zm.vec.forward(f32),
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
            self.yaw + self.pitch_yaw_speed * @as(f32, @floatCast(x - self.last_mouse_x)),
            -180.0,
            180.0,
        );
        self.pitch = std.math.clamp(
            self.pitch + self.pitch_yaw_speed * @as(f32, @floatCast(self.last_mouse_y - y)),
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
        // const view_mat = self.getViewMat(); would be ideal!
        const translation = self.translation;
        self.translation = zm.vec.zero(3, f16);
        const view_mat = self.getViewMat();
        self.translation = translation;
        return view_mat;
    }
};

pub const SkyBox = struct {
    shader_program: core.ShaderProgram,
    skybox_cube_verts: []const gl.float,
    VAO: c_uint,
    VBO: c_uint,
    TBO: c_uint,

    pub fn init(allocator: std.mem.Allocator, directory: []const u8) !SkyBox {
        // TODO: Make a default hardcoded shader program and accept a path to a custom
        // one!
        const skybox_shader_program: core.ShaderProgram = try core.ShaderProgram.init(
            allocator,
            "shaders/vertex_shader_skybox.glsl",
            "shaders/fragment_shader_skybox.glsl",
        );
        var VAOs: [1]c_uint = undefined;
        gl.GenVertexArrays(1, &VAOs);
        const vao = VAOs[0];

        var VBOs: [1]c_uint = undefined;
        gl.GenBuffers(1, &VBOs);
        const vbo: c_uint = VBOs[0];
        // Texture buffers:
        var TBOs: [1]c_uint = undefined;
        gl.GenTextures(1, &TBOs);
        const tbo: c_uint = TBOs[0];

        const skybox_cube_verts = [_]gl.float{
            -1.0, 1.0,  -1.0,
            -1.0, -1.0, -1.0,
            1.0,  -1.0, -1.0,
            1.0,  -1.0, -1.0,
            1.0,  1.0,  -1.0,
            -1.0, 1.0,  -1.0,

            -1.0, -1.0, 1.0,
            -1.0, -1.0, -1.0,
            -1.0, 1.0,  -1.0,
            -1.0, 1.0,  -1.0,
            -1.0, 1.0,  1.0,
            -1.0, -1.0, 1.0,

            1.0,  -1.0, -1.0,
            1.0,  -1.0, 1.0,
            1.0,  1.0,  1.0,
            1.0,  1.0,  1.0,
            1.0,  1.0,  -1.0,
            1.0,  -1.0, -1.0,

            -1.0, -1.0, 1.0,
            -1.0, 1.0,  1.0,
            1.0,  1.0,  1.0,
            1.0,  1.0,  1.0,
            1.0,  -1.0, 1.0,
            -1.0, -1.0, 1.0,

            -1.0, 1.0,  -1.0,
            1.0,  1.0,  -1.0,
            1.0,  1.0,  1.0,
            1.0,  1.0,  1.0,
            -1.0, 1.0,  1.0,
            -1.0, 1.0,  -1.0,

            -1.0, -1.0, -1.0,
            -1.0, -1.0, 1.0,
            1.0,  -1.0, -1.0,
            1.0,  -1.0, -1.0,
            -1.0, -1.0, 1.0,
            1.0,  -1.0, 1.0,
        };
        // Creating a skybox
        gl.BindVertexArray(vao);
        gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
        gl.BufferData(gl.ARRAY_BUFFER, @sizeOf(gl.float) * skybox_cube_verts.len, &skybox_cube_verts, gl.STATIC_DRAW);
        gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 3 * @sizeOf(gl.float), 0);
        gl.EnableVertexAttribArray(0);
        const skybox_dir = std.fs.cwd().openDir(directory, .{}) catch |err| {
            log.err("failed to open skybox directory: {?s}", .{directory});
            return err;
        };
        const file_names: []const []const u8 = &.{
            // it's the adress of you idiot.
            "right.png",
            "left.png",
            "top.png",
            "bottom.png",
            "front.png",
            "back.png",
        };
        var file: std.fs.File = undefined;
        for (file_names, 0..) |file_name, i| {
            file = skybox_dir.openFile(file_name, .{}) catch |err| {
                log.err("failed to open skybox file: {?s}", .{file_name});
                return err;
            };
            try texture.load_from_file(
                file,
                gl.TEXTURE_CUBE_MAP,
                tbo,
                gl.TEXTURE_CUBE_MAP_POSITIVE_X + @as(c_uint, @intCast(i)),
                false, // NOTE: Make sure to not use mipmaps for the skybox!
                allocator,
            );
        }
        gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MIN_FILTER, gl.LINEAR); // NOTE: Make sure to not use mipmaps for the skybox!
        gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE);
        skybox_shader_program.use();
        try skybox_shader_program.setInt("cubemap", 0); // Set the uniform to the texture unit
        return .{
            .shader_program = skybox_shader_program,
            .skybox_cube_verts = &skybox_cube_verts,
            .VAO = vao,
            .VBO = vbo,
            .TBO = tbo,
        };
    }

    pub fn draw(self: SkyBox, camera_view_mat: zm.Mat4f, projection_mat: zm.Mat4f) !void {
        gl.DepthFunc(gl.LEQUAL); // Change depth function so depth test passes when values are equal to depth buffer's content
        // gl.DepthMask(gl.FALSE); // Disable depth writing so we don't need to worry about
        // the scale of the skybox!
        self.shader_program.use();
        try self.shader_program.setMat4f("u_view", camera_view_mat, true);
        try self.shader_program.setMat4f("u_proj", projection_mat, true);
        gl.BindVertexArray(self.VAO);
        gl.DrawArrays(gl.TRIANGLES, 0, 36);
        // gl.DepthMask(gl.TRUE);
        gl.DepthFunc(gl.LESS); // Set depth function back to default
        gl.BindVertexArray(0);
    }

    pub fn deinit(self: SkyBox) void {
        self.shader_program.delete();
        var buffer: [1]c_uint = .{self.VBO};
        var vao: [1]c_uint = .{self.VAO};
        var tbo: [1]c_uint = .{self.TBO};
        gl.DeleteBuffers(1, &buffer);
        gl.DeleteVertexArrays(1, &vao);
        gl.DeleteTextures(1, &tbo);
    }
};
