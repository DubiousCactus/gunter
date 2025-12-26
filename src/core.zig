const std = @import("std");
const glfw = @import("zglfw");
const gl = @import("gl");
const zigimg = @import("zigimg");
const zm = @import("zm");

const texture = @import("texture.zig");
const asset = @import("asset.zig");

const glfw_log = std.log.scoped(.glfw);
const gl_log = std.log.scoped(.gl);
const log = std.log;

fn logGLFWError(error_code: glfw.ErrorCode, description: ?[*:0]const u8) callconv(.c) void {
    if (description) |s| {
        glfw_log.err("{}: {s}\n", .{ error_code, s });
    } else {
        glfw_log.err("{}: <no description>\n", .{error_code});
    }
}

fn getProcAddress(name: [*:0]const u8) callconv(.c) ?*align(4) const anyopaque {
    return @as(?*align(4) const anyopaque, @alignCast(glfw.getProcAddress(name)));
}

pub const Material = struct {
    ambient: zm.Vec3f,
    diffuse: zm.Vec3f,
    specular: zm.Vec3f,
    shininess: gl.float,
};

pub const TextureMaterial = struct {
    diffuse_texture_index: i32,
    specular_texture_index: i32,
    shininess: gl.float,
};

pub const PointLight = struct {
    position: zm.Vec3f,
    ambient: zm.Vec3f,
    diffuse: zm.Vec3f,
    specular: zm.Vec3f,
    constant: f32,
    linear: f32,
    quadratic: f32,
};

pub const DirectionalLight = struct {
    direction: zm.Vec3f,
    ambient: zm.Vec3f,
    diffuse: zm.Vec3f,
    specular: zm.Vec3f,
};

pub const SpotLight = struct {
    position: zm.Vec3f,
    direction: zm.Vec3f,
    inner_cutoff_angle_cosine: f32,
    outer_cutoff_angle_cosine: f32,
    ambient: zm.Vec3f,
    diffuse: zm.Vec3f,
    specular: zm.Vec3f,
    constant: f32,
    linear: f32,
    quadratic: f32,
};

pub const ShaderProgram = struct {
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
            log.err("failed to open vertex shader: {s}", .{vert_shader_pth});
            return err;
        };
        // Ensure null termination (add a null byte at the end of the slice) by setting
        // the sentinel with readToEndAllocOptions.
        var shader_src: []u8 = file.readToEndAllocOptions(
            allocator,
            1024 * 1e6,
            null,
            std.mem.Alignment.of(u8),
            0,
        ) catch |err| {
            log.err("failed to read vertex shader: {s}", .{vert_shader_pth});
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
        var success: [1]c_int = .{undefined};
        var info_log: [512:0]u8 = undefined;
        gl.GetShaderiv(vertex_shader, gl.COMPILE_STATUS, &success);
        if (success[0] != gl.TRUE) {
            gl.GetShaderInfoLog(vertex_shader, info_log.len, null, &info_log);
            gl_log.err(
                "failed to compile vertex shader '{s}': {s}",
                .{ vert_shader_pth, std.mem.sliceTo(&info_log, 0) },
            );
            return error.CompileShaderFailed;
        }
        // ===================================================
        // ================ Fragment shader ==================
        file.close();
        file = cwd.openFile(frag_shader_pth, .{}) catch |err| {
            log.err("failed to open fragment shader: {s}", .{frag_shader_pth});
            return err;
        };
        defer file.close();
        shader_src = file.readToEndAllocOptions(
            allocator,
            1024 * 1e6,
            null,
            std.mem.Alignment.of(u8),
            0,
        ) catch |err| {
            log.err("failed to read fragment shader: {s}", .{frag_shader_pth});
            return err;
        };
        defer allocator.free(shader_src);
        // Now let's create our vertex shader object:
        const frag_shader: c_uint = gl.CreateShader(gl.FRAGMENT_SHADER);
        // Next, attach the shader code to the shader object and compile it:
        // Note that we can compile one shader from multiple sources, but here we do just 1.
        gl.ShaderSource(frag_shader, 1, @ptrCast(&shader_src.ptr), null);
        gl.CompileShader(frag_shader);
        success = .{undefined};
        info_log = undefined;
        gl.GetShaderiv(frag_shader, gl.COMPILE_STATUS, &success);
        if (success[0] != gl.TRUE) {
            gl.GetShaderInfoLog(frag_shader, info_log.len, null, &info_log);
            gl_log.err("failed to compile fragment shader '{s}': {s}", .{ frag_shader_pth, std.mem.sliceTo(
                &info_log,
                0,
            ) });
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
        success = .{undefined};
        gl.GetProgramiv(shader_program, gl.LINK_STATUS, &success);
        if (success[0] != gl.TRUE) {
            info_log = undefined;
            gl.GetProgramInfoLog(shader_program, info_log.len, null, &info_log);
            gl_log.err("failed to compile fragment shader: {s}", .{std.mem.sliceTo(
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
            gl_log.err("failed to find uniform: {s}", .{name});
            return error.GetUniformLocationFailed;
        }
        gl.Uniform1ui(loc, @as(c_uint, @intFromBool(value)));
    }

    pub fn setInt(self: ShaderProgram, name: [*:0]const u8, value: i32) !void {
        const loc = gl.GetUniformLocation(self.id, name);
        if (loc == -1) {
            gl_log.err("failed to find uniform: {s}", .{name});
            return error.GetUniformLocationFailed;
        }
        gl.Uniform1i(loc, value);
    }

    pub fn setFloat(self: ShaderProgram, name: [*:0]const u8, value: f32) !void {
        const loc = gl.GetUniformLocation(self.id, name);
        if (loc == -1) {
            gl_log.err("failed to find uniform: {s}", .{name});
            return error.GetUniformLocationFailed;
        }
        gl.Uniform1f(loc, value);
    }

    pub fn setVec3f(self: ShaderProgram, name: [*:0]const u8, value: zm.Vec3f) !void {
        const loc = gl.GetUniformLocation(self.id, name);
        if (loc == -1) {
            gl_log.err("failed to find uniform: {s}", .{name});
            return error.GetUniformLocationFailed;
        }
        gl.Uniform3f(loc, value.data[0], value.data[1], value.data[2]);
    }

    pub fn setMat4f(self: ShaderProgram, name: [*:0]const u8, value: zm.Mat4f, transpose: bool) !void {
        const loc = gl.GetUniformLocation(self.id, name);
        if (loc == -1) {
            gl_log.err("failed to find uniform: {s}", .{name});
            return error.GetUniformLocationFailed;
        }
        gl.UniformMatrix4fv(loc, 1, @intFromBool(transpose), @ptrCast(&(value)));
    }

    pub fn setMaterial(self: ShaderProgram, value: Material) !void {
        try self.setVec3f("u_material.ambient", value.ambient);
        try self.setVec3f("u_material.diffuse", value.diffuse);
        try self.setVec3f("u_material.specular", value.specular);
        try self.setFloat("u_material.shininess", value.shininess);
    }

    pub fn setTextureMaterial(self: ShaderProgram, value: TextureMaterial) !void {
        try self.setInt("u_material.diffuse", value.diffuse_texture_index);
        try self.setInt("u_material.specular", value.specular_texture_index);
        try self.setFloat("u_material.shininess", value.shininess);
    }

    pub fn setDirectionalLight(self: ShaderProgram, value: DirectionalLight) !void {
        try self.setVec3f("u_dir_light.direction", value.direction);
        try self.setVec3f("u_dir_light.ambient", value.ambient);
        try self.setVec3f("u_dir_light.diffuse", value.diffuse);
        try self.setVec3f("u_dir_light.specular", value.specular);
    }

    pub fn setPointLight(self: ShaderProgram, index: ?u8, value: PointLight) !void {
        var name_buf: [64:0]u8 = undefined; // Sentinel-terminated buffer
        var suffix_buf: [32:0]u8 = undefined; // Separate buffer for suffixes

        // Build the base name (e.g., "u_point_lights[0]")
        const base = if (index) |i|
            try std.fmt.bufPrint(&name_buf, "u_point_lights[{d}]", .{i})
        else
            try std.fmt.bufPrint(&name_buf, "u_point_light", .{});
        name_buf[base.len] = 0; // Explicit null terminator

        // Iterate over suffixes at COMPILE-TIME (no runtime switching)
        inline for (.{ "position", "ambient", "diffuse", "specular", "constant", "linear", "quadratic" }) |suffix| {
            // Build the full uniform name (e.g., "u_point_lights[0].position")
            const full_name = try std.fmt.bufPrintZ(&suffix_buf, "{s}.{s}", .{ std.mem.sliceTo(&name_buf, 0), suffix });

            // Handle each case at COMPILE-TIME (no runtime string comparison)
            if (comptime std.mem.eql(u8, suffix, "position")) {
                try self.setVec3f(full_name, value.position);
            } else if (comptime std.mem.eql(u8, suffix, "ambient")) {
                try self.setVec3f(full_name, value.ambient);
            } else if (comptime std.mem.eql(u8, suffix, "diffuse")) {
                try self.setVec3f(full_name, value.diffuse);
            } else if (comptime std.mem.eql(u8, suffix, "specular")) {
                try self.setVec3f(full_name, value.specular);
            } else if (comptime std.mem.eql(u8, suffix, "constant")) {
                try self.setFloat(full_name, value.constant);
            } else if (comptime std.mem.eql(u8, suffix, "linear")) {
                try self.setFloat(full_name, value.linear);
            } else if (comptime std.mem.eql(u8, suffix, "quadratic")) {
                try self.setFloat(full_name, value.quadratic);
            }
        }
    }

    pub fn setSpotLight(self: ShaderProgram, value: SpotLight) !void {
        try self.setVec3f("u_spot_light.position", value.position);
        try self.setVec3f("u_spot_light.direction", value.direction);
        try self.setFloat("u_spot_light.inner_cutoff_angle_cosine", value.inner_cutoff_angle_cosine);
        try self.setFloat("u_spot_light.outer_cutoff_angle_cosine", value.outer_cutoff_angle_cosine);
        try self.setVec3f("u_spot_light.ambient", value.ambient);
        try self.setVec3f("u_spot_light.diffuse", value.diffuse);
        try self.setVec3f("u_spot_light.specular", value.specular);
        try self.setFloat("u_spot_light.constant", value.constant);
        try self.setFloat("u_spot_light.linear", value.linear);
        try self.setFloat("u_spot_light.quadratic", value.quadratic);
    }
};

pub const ContextOptions = struct {
    width: u16,
    height: u16,
    enable_vsync: bool,
    enable_depth_testing: bool,
    enable_blending: bool,
    grab_mouse: bool,
};

pub const Context = struct {
    window: *glfw.Window,
    progress_node: std.Progress.Node,
    options: ContextOptions,
    splash_texture: texture.Texture,
    splash_shader_program: ShaderProgram,

    /// Procedure table that will hold loaded OpenGL functions.
    gl_procs: *gl.ProcTable,

    pub fn init(allocator: std.mem.Allocator, options: ContextOptions) !Context {
        // Create an OpenGL context using a windowing system of your choice.
        _ = glfw.setErrorCallback(logGLFWError);
        try glfw.init();

        glfw.windowHint(.context_version_major, gl.info.version_major);
        glfw.windowHint(.context_version_minor, gl.info.version_minor);
        glfw.windowHint(.opengl_profile, .opengl_core_profile);
        glfw.windowHint(.opengl_forward_compat, true);
        const window = try glfw.Window.create(
            options.width,
            options.height,
            "Gunter Engine",
            null,
        );
        // Make the window's context current
        glfw.makeContextCurrent(window);
        if (options.enable_vsync) glfw.swapInterval(1);

        // Initialize the procedure table. This is a table where all OpenGL function
        // implementations are stored, because the implementations vary between drivers.
        const gl_procs: *gl.ProcTable = try allocator.create(gl.ProcTable);
        errdefer allocator.destroy(gl_procs); // Cleanup if anything below fails
        if (!gl_procs.init(getProcAddress)) {
            gl_log.err("failed to initialize OpenGL procedure table", .{});
            return error.GLInitFailed;
        }

        // Make the procedure table current on the calling thread.
        gl.makeProcTableCurrent(gl_procs);

        const root_dir = std.fs.cwd().openDir("./", .{}) catch |err| {
            log.err("failed to open directory ./ ", .{});
            return err;
        };
        const splash_file = root_dir.openFile(std.mem.sliceTo("gunter.png", 0), .{}) catch |err| {
            log.err("failed to open texture file gunter.png", .{});
            return err;
        };

        var splash_texture = texture.Texture.init(.base_color, false);
        try splash_texture.loadFromFile(splash_file, true, allocator);

        const splash_shader: ShaderProgram = try ShaderProgram.init(
            allocator,
            "shaders/vertex_shader_splash.glsl",
            "shaders/fragment_shader_splash.glsl",
        );

        return Context{
            .window = window,
            .gl_procs = gl_procs,
            .progress_node = std.Progress.start(.{}),
            .options = options,
            .splash_texture = splash_texture,
            .splash_shader_program = splash_shader,
        };
    }

    fn getMonitorWidth(self: Context) ?i32 {
        _ = self;
        var monitor_width: ?i32 = undefined;
        if (glfw.Monitor.getPrimary()) |monitor| {
            if (monitor.getVideoMode()) |mode| {
                monitor_width = mode.width;
            } else |_| {
                glfw_log.err("Could not get the video mode object\n", .{});
            }
        } else {
            glfw_log.err("Could not find the monitor object\n", .{});
        }
        return monitor_width;
    }

    fn getMonitorHeight(self: Context) ?i32 {
        _ = self;
        var monitor_height: ?i32 = undefined;
        if (glfw.Monitor.getPrimary()) |monitor| {
            if (monitor.getVideoMode()) |mode| {
                monitor_height = mode.height;
            } else |_| {
                glfw_log.err("Could not get the video mode object\n", .{});
            }
        } else {
            glfw_log.err("Could not find the monitor object\n", .{});
        }
        return monitor_height;
    }
    pub fn splashScreen(self: Context) !void {
        const width = 400;
        const height = 400;
        const monitor_width: i32 = self.getMonitorWidth() orelse 1920;
        const monitor_height: i32 = self.getMonitorHeight() orelse 1080;
        self.window.setPos(
            @divFloor(monitor_width, 2) - @divFloor(width, 2),
            @divFloor(monitor_height, 2) - @divFloor(height, 2),
        );
        self.window.setAttribute(.decorated, false);
        self.window.setAttribute(.floating, true);
        self.window.setAttribute(.resizable, false);
        self.window.setAttribute(.auto_iconify, true);

        self.splash_shader_program.use();
        var quad = asset.Primitive.makePlaneMesh();
        self.splash_texture.bind(0);
        try self.splash_shader_program.setInt("u_texture", 0);

        self.window.setSize(400, 400);
        gl.ClearColor(0.0, 0.0, 0.0, 1);
        try quad.draw(self.splash_shader_program, .{
            .use_textures = false,
        }, undefined);
        self.window.swapBuffers(); // Swap the color buffer used to render at this frame and
        glfw.pollEvents(); // checks if any events are triggered, updates the window
        // state and calls the corresponding functions which we can register via
        // callbacks.
    }

    pub fn ready(self: Context) !void {
        self.splash_texture.deinit();
        self.splash_shader_program.delete();
        // glfw.defaultWindowHints();
        self.window.setAttribute(.decorated, true);
        self.window.setAttribute(.floating, false);
        self.window.setAttribute(.resizable, false);

        const monitor_width: i32 = self.getMonitorWidth() orelse 1920;
        const monitor_height: i32 = self.getMonitorHeight() orelse 1080;
        var x_offset: i32 = 0;
        var y_offset: i32 = 0;
        if (self.options.width < monitor_width) {
            x_offset = @divFloor(monitor_width, 2) - @divFloor(self.options.width, 2);
        }
        if (self.options.height < monitor_height) {
            y_offset = @divFloor(monitor_height, 2) - @divFloor(self.options.height, 2);
        }
        self.window.setPos(x_offset, y_offset);
        self.window.setSize(self.options.width, self.options.height);
        gl.Viewport(0, 0, self.options.width, self.options.height);
        if (self.options.enable_depth_testing) gl.Enable(gl.DEPTH_TEST);
        if (self.options.enable_blending) {
            gl.Enable(gl.BLEND);
            gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
        }
        if (self.options.grab_mouse) try self.window.setInputMode(.cursor, .disabled);
        gl.ActiveTexture(gl.TEXTURE0); // Reset for good measures!
    }

    pub fn pauseDepthTesting(self: Context) void {
        _ = self;
        gl.Disable(gl.DEPTH_TEST);
    }

    pub fn resumeDepthTesting(self: Context) void {
        if (self.options.enable_depth_testing)
            gl.Enable(gl.DEPTH_TEST);
    }

    pub fn destroy(self: Context, allocator: std.mem.Allocator) void {
        allocator.destroy(self.gl_procs);
        gl.makeProcTableCurrent(null);
        glfw.makeContextCurrent(null);
        self.window.destroy();
        glfw.terminate();
        self.progress_node.end();
    }
};

pub const Ticker = struct {
    frame_times: [3]u64 = [3]u64{ 0, 0, 0 },
    timer: std.time.Timer,
    frame_delta: u64,

    pub fn init() !Ticker {
        return Ticker{ .timer = try std.time.Timer.start(), .frame_delta = 0 };
    }

    pub fn tick(self: *Ticker) void {
        const time = self.timer.read();
        self.frame_times[2] = self.frame_times[1]; // t-2
        self.frame_times[1] = self.frame_times[0]; // t-1
        self.frame_times[0] = time; // t
        self.frame_delta = self.frame_times[1] - self.frame_times[2]; // t-1 - t-2, lag=1
    }

    pub fn deltaSeconds(self: Ticker) f64 {
        return @as(f64, @floatFromInt(self.frame_delta)) / std.time.ns_per_s;
    }

    pub fn deltaMilliSeconds(self: Ticker) f64 {
        return @as(f64, @floatFromInt(self.frame_delta)) / std.time.ns_per_ms;
    }
};

pub const FramebufferTextureAttachments = struct {
    color: bool = false,
    depth: bool = false,
    stencil: bool = false,
};

pub const FramebufferRenderbufferAttachments = struct {
    depth: bool = false,
    stencil: bool = false,
};

pub const Framebuffer = struct {
    FBO: c_uint,
    texture_obj: ?texture.Texture,
    texture_attachments: FramebufferTextureAttachments,
    renderbuffer_attachments: FramebufferRenderbufferAttachments,

    pub fn initWithTexture(
        width: u16,
        height: u16,
        texture_attachments: FramebufferTextureAttachments,
        renderbuffer_attachments: FramebufferRenderbufferAttachments,
    ) !Framebuffer {
        var fbo = [1]c_uint{undefined};
        gl.GenFramebuffers(1, &fbo);
        gl.BindFramebuffer(gl.FRAMEBUFFER, fbo[0]);
        var texture_obj: texture.Texture = undefined;
        if (texture_attachments.color) {
            texture_obj = texture.Texture.init(.color_framebuffer, false);
            texture_obj.fill(width, height, 3, null);
            gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture_obj.id, 0);
        }
        if (texture_attachments.depth and texture_attachments.stencil) {
            texture_obj = texture.Texture.init(.depth_stencil_framebuffer, false);
            texture_obj.fill(width, height, 1, null);
            gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_STENCIL_ATTACHMENT, gl.TEXTURE_2D, texture_obj.id, 0);
        } else if (texture_attachments.depth) {
            texture_obj = texture.Texture.init(.depth_framebuffer, false);
            texture_obj.fill(width, height, 1, null);
            gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.TEXTURE_2D, texture_obj.id, 0);
        } else if (texture_attachments.stencil) {
            texture_obj = texture.Texture.init(.stencil_framebuffer, false);
            texture_obj.fill(width, height, 1, null);
            gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.STENCIL_ATTACHMENT, gl.TEXTURE_2D, texture_obj.id, 0);
        }
        if (renderbuffer_attachments.depth and renderbuffer_attachments.stencil) {
            var rbo: [1]c_uint = undefined;
            gl.GenRenderbuffers(1, &rbo);
            gl.BindRenderbuffer(gl.RENDERBUFFER, rbo[0]);
            gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH24_STENCIL8, width, height);
            gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_STENCIL_ATTACHMENT, gl.RENDERBUFFER, rbo[0]);
            gl.BindRenderbuffer(gl.RENDERBUFFER, 0);
        } else if (renderbuffer_attachments.depth) {
            var rbo: [1]c_uint = undefined;
            gl.GenRenderbuffers(1, &rbo);
            gl.BindRenderbuffer(gl.RENDERBUFFER, rbo[0]);
            gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, width, height);
            gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, rbo[0]);
            gl.BindRenderbuffer(gl.RENDERBUFFER, 0);
        } else if (renderbuffer_attachments.stencil) {
            var rbo: [1]c_uint = undefined;
            gl.GenRenderbuffers(1, &rbo);
            gl.BindRenderbuffer(gl.RENDERBUFFER, rbo[0]);
            gl.RenderbufferStorage(gl.RENDERBUFFER, gl.STENCIL_INDEX8, width, height);
            gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.STENCIL_ATTACHMENT, gl.RENDERBUFFER, rbo[0]);
            gl.BindRenderbuffer(gl.RENDERBUFFER, 0);
        }
        if (gl.CheckFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE) {
            gl_log.err("Couldn't validate the framebuffer completeness.\n", .{});
            return error.FramebufferIncompleteError;
        }
        return .{
            .FBO = fbo[0],
            .texture_obj = texture_obj,
            .texture_attachments = texture_attachments,
            .renderbuffer_attachments = renderbuffer_attachments,
        };
    }

    pub fn bind(self: Framebuffer) void {
        gl.BindFramebuffer(gl.FRAMEBUFFER, self.FBO);
    }

    pub fn unbind(self: Framebuffer) void {
        _ = self;
        gl.BindFramebuffer(gl.FRAMEBUFFER, 0);
    }

    pub fn clear(self: Framebuffer) void {
        if (self.texture_attachments.color) gl.Clear(gl.COLOR_BUFFER_BIT);
        if (self.texture_attachments.depth or self.renderbuffer_attachments.depth) gl.Clear(gl.DEPTH_BUFFER_BIT);
        if (self.texture_attachments.stencil or self.renderbuffer_attachments.stencil) gl.Clear(gl.STENCIL_BUFFER_BIT);
    }

    pub fn deinit(self: Framebuffer) void {
        var fbo = [1]c_uint{self.FBO};
        gl.DeleteFramebuffers(1, &fbo);
        gl.BindRenderbuffer(gl.RENDERBUFFER, 0);
        gl.BindFramebuffer(gl.FRAMEBUFFER, 0);
    }
};
