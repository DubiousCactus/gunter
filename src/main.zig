const std = @import("std");
const glfw = @import("mach-glfw");
const gl = @import("gl");
const zigimg = @import("zigimg");
const zm = @import("zm");

const glfw_log = std.log.scoped(.glfw);
const gl_log = std.log.scoped(.gl);
const log = std.log;

fn logGLFWError(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    glfw_log.err("{}: {s}\n", .{ error_code, description });
}
// TODO: Comptime generic
const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn add(self: *Vec3, other: Vec3) Vec3 {
        self.x += other.x;
        self.y += other.y;
        self.z += other.z;
        return self.*;
    }
};

const ShaderProgram = struct {
    // Shaders, shaders, shaders... And non-shading pipeline stages!
    // VERTEX SHADERS (in: single vertex, out: single vertex): Take in 3D coordinates and transform them (e.g. for wind effects, or just transforming to NDC).
    // GEOMETRY SHADERS (in: collection of vertices that form 1 primitive, out: collection
    // of potentially different number of verticies to form new primitives): Take in the output of the vertex shader, which form a primitive
    // (triangle, points, line, etc.) and generate new primitives.
    // PRIMITIVE ASSEMBLY (in: all vertices of the geometry shader that form 1+ primitives,
    // out: assembled primitives ready for rasterization): is a pipeline stage which takes as input the output of the
    // geometry shader and assembles them into another primitive shape.
    // VIEWPORT TRANSFORM? Somewhere here, OpenGL transforms the NDC vertices to
    // screen-space coordinates. Or is it done after rasterization?
    // RASTERIZATION (in: primitive shapes, out: pixels): is a pipeline stage which takes in
    // all primitive shapes and rasterizes them into "active pixels" / fragments. It also is
    // followed by clipping which removes all pixels that aren't visible on screen.
    // FRAGMENT SHADER (in: empty pixels / fragments, out: coloured pixels): Put some colour into our
    // pixels! The input is a "fragment", which is a data structure that contains everything
    // needed to generate coloured pixels (light, shadows, etc.). <-- All fancy effects happen here my friend.
    // TESTS AND BLENDING (in: coloured pixels, out: coloured pixels): This last stage
    // checks the depth of the fragment to do occlusion testing and alpha blending.
    // + TESSELLATION AND TRASNFORM FEEDBACK LOOP??? (will see later)
    // /!\ There are no default vertex and fragment shaders! We *need* to define those.
    // IMPORTANT: The pipeline only works on Normalized Device Coordinates! So we, the user,
    // need to take care of transforming our world vertices to NDC vertices (perspective
    // transform, etc.). But this is typically done in the vertex shader actually.
    //
    //
    id: c_uint,

    pub fn init(
        allocator: std.mem.Allocator,
        vert_shader_pth: []const u8,
        frag_shader_pth: []const u8,
    ) !ShaderProgram {
        const cwd = std.fs.cwd();

        // ================ Vertex shader ====================
        var file = cwd.openFile(vert_shader_pth, .{}) catch |err| {
            log.err("failed to open vertex shader: {?s}", .{vert_shader_pth});
            return err;
        };
        // Ensure null termination (add a null byte at the end of the slice) by setting
        // the sentinel with readToEndAllocOptions.
        var shader_src: []u8 = file.readToEndAllocOptions(
            allocator,
            1024,
            null,
            @alignOf(u8),
            0,
        ) catch |err| {
            log.err("failed to read vertex shader: {?s}", .{vert_shader_pth});
            return err;
        };
        defer allocator.free(shader_src);
        // Now let's create our vertex shader object:
        const vertex_shader: c_uint = gl.CreateShader(gl.VERTEX_SHADER);
        // Next, attach the shader code to the shader object and compile it:
        // Note that we can compile one shader from multiple sources, but here we do just 1.
        // We first convert the slice to a many-item pointer:
        const shader_src_ptr: [*]const u8 = shader_src.ptr; // The cast to const is implicit.
        // Then, we take a pointer to that many-item pointer with &shader_src_ptr, and
        // we wrap it in a slice to take a many-item pointer to the first item.
        // const container: [*]const [*]const u8 = (&shader_src_ptr)[0..1];
        // A cleaner approach, casting a pointer to the many-item pointer (ie *[*]const
        // u8), to a many-item pointer to many-item pointers:
        const container: [*]const [*]const u8 = @ptrCast(&shader_src_ptr);
        gl.ShaderSource(vertex_shader, 1, container, null);
        gl.CompileShader(vertex_shader);
        var success: c_int = undefined;
        var info_log: [512:0]u8 = undefined;
        gl.GetShaderiv(vertex_shader, gl.COMPILE_STATUS, &success);
        if (success != gl.TRUE) {
            gl.GetShaderInfoLog(vertex_shader, info_log.len, null, &info_log);
            gl_log.err(
                "failed to compile vertex shader: {?s}",
                .{std.mem.sliceTo(&info_log, 0)},
            );
            return error.CompileShaderFailed;
        }
        // ===================================================
        // ================ Fragment shader ==================
        file.close();
        file = cwd.openFile(frag_shader_pth, .{}) catch |err| {
            log.err("failed to open fragment shader: {?s}", .{frag_shader_pth});
            return err;
        };
        defer file.close();
        shader_src = file.readToEndAllocOptions(
            allocator,
            1024,
            null,
            @alignOf(u8),
            0,
        ) catch |err| {
            log.err("failed to read fragment shader: {?s}", .{frag_shader_pth});
            return err;
        };
        defer allocator.free(shader_src);
        // Now let's create our vertex shader object:
        const frag_shader: c_uint = gl.CreateShader(gl.FRAGMENT_SHADER);
        // Next, attach the shader code to the shader object and compile it:
        // Note that we can compile one shader from multiple sources, but here we do just 1.
        gl.ShaderSource(frag_shader, 1, @ptrCast(&shader_src.ptr), null);
        gl.CompileShader(frag_shader);
        success = undefined;
        info_log = undefined;
        gl.GetShaderiv(frag_shader, gl.COMPILE_STATUS, &success);
        if (success != gl.TRUE) {
            gl.GetShaderInfoLog(frag_shader, info_log.len, null, &info_log);
            gl_log.err("failed to compile vertex shader: {?s}", .{std.mem.sliceTo(
                &info_log,
                0,
            )});
            return error.CompileShaderFailed;
        }

        // Now that we compile both shader objects, we need to build the shader program.
        // It's a linked version of multiple shaders combined. When we render something, we
        // then activate this shader program and it'll be used for render calls.
        // Building this program allows to link the inputs and outputs together, to create
        // the chain of shaders that fits in the pipeline. Neat :)
        const shader_program: c_uint = gl.CreateProgram();
        if (shader_program == 0) return error.CreateProgramFailed;
        errdefer gl.DeleteProgram(shader_program);

        gl.AttachShader(shader_program, vertex_shader);
        gl.AttachShader(shader_program, frag_shader);
        gl.LinkProgram(shader_program);
        success = undefined;
        gl.GetProgramiv(shader_program, gl.LINK_STATUS, &success);
        if (success != gl.TRUE) {
            info_log = undefined;
            gl.GetProgramInfoLog(shader_program, info_log.len, null, &info_log);
            gl_log.err("failed to compile fragment shader: {?s}", .{std.mem.sliceTo(
                &info_log,
                0,
            )});
            return error.CompileShaderFailed;
        }
        // We don't need the shader objects anymore:
        gl.DeleteShader(frag_shader);
        gl.DeleteShader(vertex_shader);
        return ShaderProgram{ .id = shader_program };
    }

    pub fn delete(self: ShaderProgram) void {
        gl.DeleteProgram(self.id);
    }

    pub fn use(self: ShaderProgram) void {
        gl.UseProgram(self.id);
    }

    // TODO: Use comptime to implement a generic set()
    pub fn setBool(self: ShaderProgram, name: [*:0]const u8, value: bool) !void {
        const loc = gl.GetUniformLocation(self.id, name);
        if (loc == -1) {
            gl_log.err("failed to find uniform: {?s}", .{name});
            return error.GetUniformLocationFailed;
        }
        gl.Uniform1ui(loc, @as(c_uint, @intFromBool(value)));
    }

    pub fn setInt(self: ShaderProgram, name: [*:0]const u8, value: i32) !void {
        const loc = gl.GetUniformLocation(self.id, name);
        if (loc == -1) {
            gl_log.err("failed to find uniform: {?s}", .{name});
            return error.GetUniformLocationFailed;
        }
        gl.Uniform1i(loc, value);
    }

    pub fn setFloat(self: ShaderProgram, name: [*:0]const u8, value: f32) !void {
        const loc = gl.GetUniformLocation(self.id, name);
        if (loc == -1) {
            gl_log.err("failed to find uniform: {?s}", .{name});
            return error.GetUniformLocationFailed;
        }
        gl.Uniform1f(loc, value);
    }

    pub fn setVec3f(self: ShaderProgram, name: [*:0]const u8, value: zm.Vec3f) !void {
        const loc = gl.GetUniformLocation(self.id, name);
        if (loc == -1) {
            gl_log.err("failed to find uniform: {?s}", .{name});
            return error.GetUniformLocationFailed;
        }
        gl.Uniform3f(loc, value[0], value[1], value[2]);
    }

    pub fn setMat4f(self: ShaderProgram, name: [*:0]const u8, value: zm.Mat4f, transpose: bool) !void {
        const loc = gl.GetUniformLocation(self.id, name);
        if (loc == -1) {
            gl_log.err("failed to find uniform: {?s}", .{name});
            return error.GetUniformLocationFailed;
        }
        gl.UniformMatrix4fv(loc, 1, @intFromBool(transpose), @ptrCast(&(value)));
    }
};

const Context = struct {
    window: glfw.Window,

    /// Procedure table that will hold loaded OpenGL functions.
    gl_procs: *gl.ProcTable,

    pub fn init(
        allocator: std.mem.Allocator,
        width: u16,
        height: u16,
        enable_vsync: bool,
        enable_depth_testing: bool,
        grab_mouse: bool,
    ) !Context {
        // Create an OpenGL context using a windowing system of your choice.
        glfw.setErrorCallback(logGLFWError);
        if (!glfw.init(.{})) {
            glfw_log.err("failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
            return error.GLFWInitFailed;
        }

        const window = glfw.Window.create(width, height, "OpenGL", null, null, .{
            .context_version_major = gl.info.version_major,
            .context_version_minor = gl.info.version_minor,
            .opengl_profile = .opengl_core_profile,
            .opengl_forward_compat = true,
        }) orelse {
            glfw_log.err("failed to create GLFW window: {?s}", .{glfw.getErrorString()});
            return error.CreateWindowFailed;
        };
        // Make the window's context current
        glfw.makeContextCurrent(window);
        if (enable_vsync) glfw.swapInterval(1);

        // Initialize the procedure table. This is a table where all OpenGL function
        // implementations are stored, because the implementations vary between drivers.
        const gl_procs = try allocator.create(gl.ProcTable);
        errdefer allocator.destroy(gl_procs); // Cleanup if anything below fails
        if (!gl_procs.init(glfw.getProcAddress)) {
            gl_log.err("failed to initialize OpenGL procedure table", .{});
            return error.GLInitFailed;
        }

        // Make the procedure table current on the calling thread.
        gl.makeProcTableCurrent(gl_procs);

        if (enable_depth_testing) gl.Enable(gl.DEPTH_TEST);
        if (grab_mouse) window.setInputModeCursor(.disabled);

        return Context{
            .window = window,
            .gl_procs = gl_procs,
        };
    }

    pub fn destroy(self: Context, allocator: std.mem.Allocator) void {
        allocator.destroy(self.gl_procs);
        gl.makeProcTableCurrent(null);
        glfw.makeContextCurrent(null);
        self.window.destroy();
        glfw.terminate();
    }
};

const screen_w = 1920;
const screen_h = 1080;

const Camera = struct {
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
    ticker: *Ticker,

    pub fn init(ticker: *Ticker, translation: ?zm.Vec3f) Camera {
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

const Ticker = struct {
    last_frame: u64 = 0,
    timer: std.time.Timer,
    frame_delta: u64,

    pub fn init() !Ticker {
        return Ticker{ .timer = try std.time.Timer.start(), .frame_delta = 0 };
    }

    pub fn tick(self: *Ticker) void {
        const time = self.timer.read();
        self.frame_delta = time - self.last_frame;
        self.last_frame = time;
    }

    pub fn deltaSeconds(self: Ticker) f64 {
        return @as(f64, @floatFromInt(self.frame_delta)) / std.time.ns_per_s;
    }

    pub fn deltaMilliSeconds(self: Ticker) f64 {
        return @as(f64, @floatFromInt(self.frame_delta)) / std.time.ns_per_ms;
    }
};

const InputHandler = struct {
    cam: *Camera,
    display_skybox: bool = false,

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
                    self.display_skybox = !self.display_skybox;
                },
                else => {},
            }
        }
        // TODO: It would be very nice to be able to hook any functions with a given key
        // + action, so that we can do anything from user code without touching the
        // input handler. For this we would need a Map of .{keycode, action} -> comptime fn or something like that.
    }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    // =========================== Initialize OpenGL + GLFW ===========================
    var context = try Context.init(allocator, screen_w, screen_h, true, true, true);
    defer context.destroy(allocator);
    var ticker = try Ticker.init();
    var camera = Camera{ .translation = zm.Vec3f{ 0, 0, -3 }, .ticker = &ticker };
    var input_handler = InputHandler.init(&camera);

    context.window.setUserPointer(&input_handler);
    context.window.setCursorPosCallback(struct {
        fn anonymous_callback(window: glfw.Window, x: f64, y: f64) void {
            const user_ptr = window.getUserPointer(InputHandler);
            if (user_ptr != null) {
                user_ptr.?.mouseCallback(x, y);
            }
        }
    }.anonymous_callback);
    context.window.setKeyCallback(struct {
        fn anonymous_callback(window: glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: glfw.Mods) void {
            const user_ptr = window.getUserPointer(InputHandler);
            if (user_ptr != null) {
                user_ptr.?.keyCallback(window, key, scancode, action, mods);
            }
        }
    }.anonymous_callback);
    // ===================================================================================
    // ===================================== Shaders =====================================
    const light_shader_program: ShaderProgram = try ShaderProgram.init(
        allocator,
        "shaders/vertex_shader_light.glsl",
        "shaders/fragment_shader_light.glsl",
    );
    defer light_shader_program.delete();
    const textured_shader_program: ShaderProgram = try ShaderProgram.init(
        allocator,
        "shaders/vertex_shader_texture.glsl",
        "shaders/fragment_shader_texture.glsl",
    );
    defer textured_shader_program.delete();
    const skybox_shader_program: ShaderProgram = try ShaderProgram.init(
        allocator,
        "shaders/vertex_shader_skybox.glsl",
        "shaders/fragment_shader_skybox.glsl",
    );
    defer skybox_shader_program.delete();
    // ===================================================================================
    // ============================ VBOS, VAOs, and VEOs =================================
    // Let's define triangle vertices in NDC:
    const vertices = [_]gl.float{
        // zig fmt: off
        // Vertex pos           Vertex color     Texture coords
        -0.5, -0.5, 0.0,        1.0, 0.2, 0.3, // bottom left
         0.5, -0.5, 0.0,        0.8, 0.0, 0.9, // bottom right
         0.0,  0.5, 0.0,        0.5, 0.1, 0.6, // top
    };
    const tri_indices = [_]gl.uint{
        0, 1, 2, // our triangle is made of these 3 vertices
    };

    // Now let's define triangle vertices in NDC, but for a cube:
    const rect_vertices = [_]gl.float{
        // positions         texture coords
        -0.5, -0.5, -0.5,  0.0, 0.0,
     0.5, -0.5, -0.5,  1.0, 0.0,
     0.5,  0.5, -0.5,  1.0, 1.0,
     0.5,  0.5, -0.5,  1.0, 1.0,
    -0.5,  0.5, -0.5,  0.0, 1.0,
    -0.5, -0.5, -0.5,  0.0, 0.0,

    -0.5, -0.5,  0.5,  0.0, 0.0,
     0.5, -0.5,  0.5,  1.0, 0.0,
     0.5,  0.5,  0.5,  1.0, 1.0,
     0.5,  0.5,  0.5,  1.0, 1.0,
    -0.5,  0.5,  0.5,  0.0, 1.0,
    -0.5, -0.5,  0.5,  0.0, 0.0,

    -0.5,  0.5,  0.5,  1.0, 0.0,
    -0.5,  0.5, -0.5,  1.0, 1.0,
    -0.5, -0.5, -0.5,  0.0, 1.0,
    -0.5, -0.5, -0.5,  0.0, 1.0,
    -0.5, -0.5,  0.5,  0.0, 0.0,
    -0.5,  0.5,  0.5,  1.0, 0.0,

     0.5,  0.5,  0.5,  1.0, 0.0,
     0.5,  0.5, -0.5,  1.0, 1.0,
     0.5, -0.5, -0.5,  0.0, 1.0,
     0.5, -0.5, -0.5,  0.0, 1.0,
     0.5, -0.5,  0.5,  0.0, 0.0,
     0.5,  0.5,  0.5,  1.0, 0.0,

    -0.5, -0.5, -0.5,  0.0, 1.0,
     0.5, -0.5, -0.5,  1.0, 1.0,
     0.5, -0.5,  0.5,  1.0, 0.0,
     0.5, -0.5,  0.5,  1.0, 0.0,
    -0.5, -0.5,  0.5,  0.0, 0.0,
    -0.5, -0.5, -0.5,  0.0, 1.0,

    -0.5,  0.5, -0.5,  0.0, 1.0,
     0.5,  0.5, -0.5,  1.0, 1.0,
     0.5,  0.5,  0.5,  1.0, 0.0,
     0.5,  0.5,  0.5,  1.0, 0.0,
    -0.5,  0.5,  0.5,  0.0, 0.0,
    -0.5,  0.5, -0.5,  0.0, 1.0,
    };



    const skybox_cube_verts = [_]gl.float{
        -1.0, 1.0, -1.0,
        -1.0, -1.0, -1.0,
         1.0, -1.0, -1.0,
         1.0, -1.0, -1.0,
         1.0,  1.0, -1.0,
        -1.0,  1.0, -1.0,

        -1.0, -1.0,  1.0,
        -1.0, -1.0, -1.0,
        -1.0,  1.0, -1.0,
        -1.0,  1.0, -1.0,
        -1.0,  1.0,  1.0,
        -1.0, -1.0,  1.0,

         1.0, -1.0, -1.0,
         1.0, -1.0,  1.0,
         1.0,  1.0,  1.0,
         1.0,  1.0,  1.0,
         1.0,  1.0, -1.0,
         1.0, -1.0, -1.0,

        -1.0, -1.0,  1.0,
        -1.0,  1.0,  1.0,
         1.0,  1.0,  1.0,
         1.0,  1.0,  1.0,
         1.0, -1.0,  1.0,
        -1.0, -1.0,  1.0,

        -1.0,  1.0, -1.0,
         1.0,  1.0, -1.0,
         1.0,  1.0,  1.0,
         1.0,  1.0,  1.0,
        -1.0,  1.0,  1.0,
        -1.0,  1.0, -1.0,

        -1.0, -1.0, -1.0,
        -1.0, -1.0,  1.0,
         1.0, -1.0, -1.0,
         1.0, -1.0, -1.0,
        -1.0, -1.0,  1.0,
         1.0, -1.0,  1.0,
    };


    // Now we need to tell OpenGL how much GPU memory it has for the vertex data. Then the
    // vertex shader will process all the GPU memory (interpreted as a collection of
    // vertices). To do so, we create Vertex Buffer Objects (VBOs). One VBO can store *a
    // large amount of vertices* in the GPU's memory. So by putting together many vertices
    // (i.e. for one mesh) inside a VBO, we can ship it from CPU memory to GPU memory in one
    // go. Of course, GPU memory is not unlimited so we need to manage the VBOs carefully,
    // depending on how many vertices in our scene we have to process. Let's create our VBO
    // for the triangle:
    var VBOs: [4]c_uint = undefined;
    gl.GenBuffers(4, &VBOs);
    defer gl.DeleteBuffers(4, &VBOs);
    const triangle_vbo: c_uint = VBOs[0];
    const cube_vbo: c_uint = VBOs[1];
    const light_cube_vbo: c_uint = VBOs[2];
    const skybox_vbo: c_uint = VBOs[3];

    // We will create Element Buffer Objects for the indices:
    var EBOs: [1]c_uint = undefined;
    gl.GenBuffers(1, &EBOs);
    defer gl.DeleteBuffers(3, &EBOs);
    const triangle_ebo: c_uint = EBOs[0];

    // Texture buffers:
    var TBOs: [3]c_uint = undefined;
    gl.GenTextures(3, &TBOs);
    defer gl.DeleteTextures(2, &TBOs);
    const cube_tbo_a: c_uint = TBOs[0];
    const cube_tbo_b: c_uint = TBOs[1];
    const cubemap_tbo: c_uint = TBOs[2];

    // We are still not ready to draw our triangle! We need to tell OpenGL how to link
    // the vertex attributes into the vertex shader, or how to interpret the allocated
    // memory in the VBO.
    // In our VBO, we just concatenated our vertex data as follows:
    // [x0, y0, z0, x1, y1, z1, x2, y2, z2]
    // So we need to tell OpenGL a few things:
    const index: c_uint = 0; // This is the position of the vertex attribute in the
    // shader. We set layout (location = 0), so we use 0. If we had more than 1 vertex
    // attribute, we'd use 1, 2, etc.
    const size: c_int = 3; // It's a vec3, 3 means how many 32-bit floats
    const type_ = gl.FLOAT; // Type of the data
    const normalized = gl.FALSE; // Should the data be normalized? (don't know how this
    // is used)
    const stride = 6 * @sizeOf(gl.float); // The stride of a vertex (it has 3 float
    // attributes, plus 3 for colour) in bytes. In practice, if the data  is tightly packed as in this
    // case, we can set it to 0.
    const pos_pointer = 0; // Offset of where the position data begins in the buffer.
    const col_pointer = 3 * @sizeOf(gl.float); // Offset of where the colour data begins in the buffer.

    // Okay we're getting really close! We now need to define a Vertex Array Object,
    // which is an abstraction to encapsulate many VBOs for efficient drawing. It allows
    // to store all VBO and VBO attribute configurations into an object, so that we can
    // swap between different VBOs and their configurations easily. It's like a container for
    // all the VBOs and their configurations.
    // It's required to use a VAO anyway, so let's go:
    var VAOs: [4]c_uint = undefined;
    gl.GenVertexArrays(4, &VAOs);
    defer gl.DeleteVertexArrays(4, &VAOs);
    const triangle_vao = VAOs[0];
    const cube_vao = VAOs[1];
    const light_cube_vao = VAOs[2];
    const skybox_vao = VAOs[3];
    // First it's important to start by binding the VAO:
    gl.BindVertexArray(triangle_vao);
    defer gl.BindVertexArray(0); // Unbind the VAO later
    // Then we bind the VBO to the bound VAO:
    gl.BindBuffer(gl.ARRAY_BUFFER, triangle_vbo); // This sets the current active buffer. Any later
    // calls to buffer alteration functions will act on the bound buffer.
    defer gl.BindBuffer(gl.ARRAY_BUFFER, 0); // Unbind the buffer
    // We'll start by copying our vertex data to the buffer:
    gl.BufferData(gl.ARRAY_BUFFER, @sizeOf(gl.float) * vertices.len, &vertices, gl.STATIC_DRAW);
    // That last parameter, .STATIC_DRAW, says that the data is set only once and used
    // by the GPU many times. If we wanted to change the data a lot, we'd use
    // .DYNAMIC_DRAW for example.
    // And specify the VBO configuration:
    gl.VertexAttribPointer(index, size, type_, normalized, stride, pos_pointer);
    // Now we need to enable the vertex attribute, because it's disabled by default.
    gl.EnableVertexAttribArray(index);
    // Now we set the attribute pointer for the colours input and enable that attribute
    // array:
    gl.VertexAttribPointer(1, size, type_, normalized, stride, col_pointer);
    gl.EnableVertexAttribArray(1);
    // Now for the EBO:
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, triangle_ebo); // Note that when we bind an
    // EBO while a VAO is bound, the VAO will keep track of it and store it. This means
    // that we can just switch VAOs and it will rebinds to the EBO. But we have to be
    // careful not to unbind the EBO while the VAO is still bound.
    defer gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0);
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, @sizeOf(gl.uint) * tri_indices.len, &tri_indices, gl.STATIC_DRAW);

    gl.BindVertexArray(cube_vao);
    defer gl.BindVertexArray(0);
    gl.BindBuffer(gl.ARRAY_BUFFER, cube_vbo);
    defer gl.BindBuffer(gl.ARRAY_BUFFER, 0);
    gl.BufferData(gl.ARRAY_BUFFER, @sizeOf(gl.float) * rect_vertices.len, &rect_vertices, gl.STATIC_DRAW);
    gl.VertexAttribPointer(index, size, type_, normalized, 5 * @sizeOf(gl.float), pos_pointer);
    gl.EnableVertexAttribArray(index);
    gl.VertexAttribPointer(1, 2, type_, normalized, 5 * @sizeOf(gl.float), 3 * @sizeOf(gl.float));
    gl.EnableVertexAttribArray(1);
    // Texture unit (assign a location value for the *uniform* sampler in the shader):
    gl.ActiveTexture(gl.TEXTURE0); // This activates the texture unit.
    // Bind the texture to the active texture unit:
    gl.BindTexture(gl.TEXTURE_2D, cube_tbo_a);
    // Set how we wrap the parameters S and T
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.MIRRORED_REPEAT);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.MIRRORED_REPEAT);
    // What happens if we have a low resolution texture but a high resolution OpenGL
    // primitive? i.e. fragment interpolation may give us 100 fragments between two
    // vertices, and between the two texture coordinates that we gave, there may only be
    // 10 pixels (if we talk about a line). So OpenGL needs to figure out which texture
    // pixel (texel) to assign to the texture coordinate, interpolated from our
    // vertex-texture coordinates. This is called *texture filtering*. We can pick
    // nearest or linear for linear interpolation. We need to set: MIN_FILTER for
    // minifying and MAG_FILTER for magnifying.
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    // To prevent aliasing due to to oversampling, which happens when the texture
    // resolution is much higher than the size of the texture on screen (ie the fragment
    // spans multiple texels), we can use Mipmaps. These are resolution pyramids of the
    // texture, where each level is half the resolution of the previous one. Thankfully,
    // OpenGL can generate those for us (see after loading the image).
    // And to prevent artifacts like the sharp edges visible between two mipmap levels,
    // we can apply some filtering between the levels when minifying:
    // NOTE: We have to override the previous setting though
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
    var image: zigimg.Image = try zigimg.Image.fromFilePath(allocator, "textures/wood.png");
    errdefer image.deinit();
    // TexImage2D uses the currently bound texture object!
    gl.TexImage2D(
        gl.TEXTURE_2D,
        0,
        if (image.pixelFormat().isRgba()) gl.RGBA else gl.RGB,
        @as(c_int, @intCast(image.width)),
        @as(c_int, @intCast(image.height)),
        0,
        if (image.pixelFormat().isRgba()) gl.RGBA else gl.RGB,
        gl.UNSIGNED_BYTE,
        image.rawBytes().ptr,
    );
    gl.GenerateMipmap(gl.TEXTURE_2D);
    image.deinit();
    // Let's do the second texture:
    gl.ActiveTexture(gl.TEXTURE1);
    gl.BindTexture(gl.TEXTURE_2D, cube_tbo_b);
    image = try zigimg.Image.fromFilePath(allocator, "textures/blood.png");
    errdefer image.deinit();
    gl.TexImage2D(
        gl.TEXTURE_2D,
        0,
        if (image.pixelFormat().isRgba()) gl.RGBA else gl.RGB,
        @as(c_int, @intCast(image.width)),
        @as(c_int, @intCast(image.height)),
        0,
        if (image.pixelFormat().isRgba()) gl.RGBA else gl.RGB,
        gl.UNSIGNED_BYTE,
        image.rawBytes().ptr,
    );
    gl.GenerateMipmap(gl.TEXTURE_2D);
    image.deinit();
    textured_shader_program.use(); // We have to .use() the program to be able to set
    // the uniforms, as they don't exist outside this particular program!
    try textured_shader_program.setInt("texture1", 0);
    try textured_shader_program.setInt("texture2", 1);

    // Creating a skybox
    gl.BindVertexArray(skybox_vao);
    // defer gl.BindVertexArray(0);
    gl.BindBuffer(gl.ARRAY_BUFFER, skybox_vbo);
    // defer gl.BindBuffer(gl.ARRAY_BUFFER, 0);
    gl.BufferData(gl.ARRAY_BUFFER, @sizeOf(gl.float) * skybox_cube_verts.len, &skybox_cube_verts, gl.STATIC_DRAW);
    gl.VertexAttribPointer(0, size, type_, normalized, 3 * @sizeOf(gl.float), 0);
    gl.EnableVertexAttribArray(0);
    gl.ActiveTexture(gl.TEXTURE0);
    gl.BindTexture(gl.TEXTURE_CUBE_MAP, cubemap_tbo); // Binds to the active texture
    // unit
    const skybox_dir = std.fs.cwd().openDir("textures/skybox", .{}) catch |err| {
        log.err("failed to open skybox directory: {?s}", .{"textures/skybox"});
        return err;
    };
    const file_names: []const []const u8 = &.{ // TODO: What's this & syntax again? lol
        // it's the adress of you idiot.
        "right.png",
        "left.png",
        "top.png",
        "bottom.png",
        "front.png",
        "back.png",
    };
    var file: ?std.fs.File = undefined;
    for (file_names, 0..) |file_name, i| {
        file = skybox_dir.openFile(file_name, .{}) catch |err| {
            log.err("failed to open skybox file: {?s}", .{file_name});
            return err;
        };
        image = try zigimg.Image.fromFile(allocator, &file.?);
        errdefer image.deinit();
        gl.TexImage2D(
            gl.TEXTURE_CUBE_MAP_POSITIVE_X+@as(c_uint, @intCast(i)),
            0,
            gl.RGB,
            @as(c_int, @intCast(image.width)),
            @as(c_int, @intCast(image.height)),
            0,
            if (image.pixelFormat().isRgba()) gl.RGBA else gl.RGB,
            gl.UNSIGNED_BYTE,
            image.rawBytes().ptr,
        );
        image.deinit();
    }
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE);
    skybox_shader_program.use();
    try skybox_shader_program.setInt("cubemap", 0); // Set the uniform to the texture unit


    gl.BindVertexArray(light_cube_vao);
    defer gl.BindVertexArray(0);
    gl.BindBuffer(gl.ARRAY_BUFFER, light_cube_vbo);
    defer gl.BindBuffer(gl.ARRAY_BUFFER, 0);
    gl.BufferData(gl.ARRAY_BUFFER, @sizeOf(gl.float) * rect_vertices.len, &rect_vertices, gl.STATIC_DRAW);
    gl.VertexAttribPointer(index, size, type_, normalized, 5 * @sizeOf(gl.float), pos_pointer);
    gl.EnableVertexAttribArray(index);
    
    // ===================================================================================
    gl.ClearColor(0.0, 0.0, 0.0, 1);
    var active_shader_program: ShaderProgram = textured_shader_program;
    var model_mat: zm.Mat4f = zm.Mat4f.multiply(
        zm.Mat4f.fromQuaternion(
            zm.Quaternionf.fromAxisAngle(
                zm.Vec3f{1.0, 0.0, 0.0},
                std.math.degreesToRadians(-55.0)
            )
        ),
        zm.Mat4f.scaling(1.0, 1.0, 1.0)
    );
    const projection_mat = zm.Mat4f.perspective(45, 1, 0.1, 1000);
    
    const cube_positions = [_]zm.Vec3f{
        zm.Vec3f{-2.4, 0.7, -0.8},
        zm.Vec3f{2.0, 5.0, -15.0},
        zm.Vec3f{-1.5, -2.2, -2.5},
        zm.Vec3f{-3.8, -2.0, -12.3},
        zm.Vec3f{2.4, -0.4, -3.5},
        zm.Vec3f{-1.7, 3.0, -7.5},
        zm.Vec3f{1.3, -2.0, -2.5},
        zm.Vec3f{1.5, 2.0, -2.5},
        zm.Vec3f{1.5, 0.2, -1.5},
        zm.Vec3f{-1.3, 1.0, -1.5},
    };
    var cube_transforms : [10]zm.Mat4f = undefined;
    for (cube_positions, 0..) |pos, i| {
        const cube_rot = zm.Mat4f.fromQuaternion(
            zm.Quaternionf.fromAxisAngle(
                zm.Vec3f{1.0, 0.3, 0.5},
                std.math.degreesToRadians(20.0 * @as(f32, @floatFromInt(i))),
            )
        );
        cube_transforms[i] = zm.Mat4f.translationVec3(pos).multiply(model_mat.multiply(cube_rot));
    }
    gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL);


    // Wait for the user to close the window. This is the render loop!
    while (!context.window.shouldClose()) {
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT); // Clear the color and z buffers
        ticker.tick();

        

        if (!input_handler.display_skybox) {
            light_shader_program.use();
            active_shader_program = light_shader_program;
            try active_shader_program.setBool("isSource", true);
            try active_shader_program.setVec3f("lightColor", zm.Vec3f{1.0, 1.0, 1.0});
            try active_shader_program.setVec3f("objColor", zm.Vec3f{0.1, 0.6, 0.05});
            try active_shader_program.setMat4f("view", camera.getViewMat(), true);
            try active_shader_program.setMat4f("projection", projection_mat, true);
            try active_shader_program.setMat4f("model", zm.Mat4f.scaling(0.3, 0.3, 0.3), true,); 
            gl.BindVertexArray(light_cube_vao);
            gl.DrawArrays(gl.TRIANGLES, 0, 36);
            try active_shader_program.setBool("isSource", false);
        } else {
            textured_shader_program.use();
            active_shader_program = textured_shader_program;
        }
        // we need to transpose to go column-major (OpenGL) since zm is
        // row-major.
        try active_shader_program.setMat4f("view", camera.getViewMat(), true);
        try active_shader_program.setMat4f("projection", projection_mat, true);
        gl.BindVertexArray(cube_vao);
        for (cube_transforms) |cube_transform| {
            try active_shader_program.setMat4f("model", cube_transform, true,); 
            gl.DrawArrays(gl.TRIANGLES, 0, 36);
        }
        if (input_handler.display_skybox) {
            // ================= SkyBox =====================
            gl.DepthFunc(gl.LEQUAL); // Change depth function so depth test passes when values are equal to depth buffer's content
            // gl.DepthMask(gl.FALSE); // Disable depth writing so we don't need to worry about
            // the scale of the skybox!
            skybox_shader_program.use();
            // try skybox_shader_program.setMat4f("view", camera.getSkyboxViewMat(), true);
            try skybox_shader_program.setMat4f("view", zm.Mat4f.identity(), true);
            try skybox_shader_program.setMat4f("projection", projection_mat, true);
            gl.BindVertexArray(skybox_vao);
            gl.DrawArrays(gl.TRIANGLES, 0, 36);
            // gl.DepthMask(gl.TRUE);
            gl.DepthFunc(gl.LESS); // Set depth function back to default
            // ==============================================
        }


        context.window.swapBuffers(); // Swap the color buffer used to render at this frame and
        // show it in the window.
        // DOUBLE BUFFERING: To prevent flickering  caused by pixel-by-pixel drawing to
        // the screen, we use a double buffer approach. It's simply one buffer where we
        // put the data (the back buffer), and one buffer that is full and ready to draw
        // (the front buffer).
        glfw.pollEvents(); // checks if any events are triggered, updates the window
        // state and calls the corresponding functions which we can register via
        // callbacks.
        //
    }
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
