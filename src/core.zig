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
            log.err("failed to open vertex shader: {?s}", .{vert_shader_pth});
            return err;
        };
        // Ensure null termination (add a null byte at the end of the slice) by setting
        // the sentinel with readToEndAllocOptions.
        var shader_src: []u8 = file.readToEndAllocOptions(
            allocator,
            1024 * 1e6,
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
                "failed to compile vertex shader '{s}': {?s}",
                .{ vert_shader_pth, std.mem.sliceTo(&info_log, 0) },
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
            1024 * 1e6,
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
            gl_log.err("failed to compile fragment shader '{s}': {?s}", .{ frag_shader_pth, std.mem.sliceTo(
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
        try self.setBool("u_is_textured", true);
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
    window: glfw.Window,

    /// Procedure table that will hold loaded OpenGL functions.
    gl_procs: *gl.ProcTable,

    pub fn init(allocator: std.mem.Allocator, options: ContextOptions) !Context {
        // Create an OpenGL context using a windowing system of your choice.
        glfw.setErrorCallback(logGLFWError);
        if (!glfw.init(.{})) {
            glfw_log.err("failed to initialize GLFW: {?s}", .{glfw.getErrorString()});
            return error.GLFWInitFailed;
        }

        const window = glfw.Window.create(options.width, options.height, "Gunter", null, null, .{
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
        if (options.enable_vsync) glfw.swapInterval(1);

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

        if (options.enable_depth_testing) gl.Enable(gl.DEPTH_TEST);
        if (options.enable_blending) {
            gl.Enable(gl.BLEND);
            gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
        }
        if (options.grab_mouse) window.setInputModeCursor(.disabled);

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

pub const Ticker = struct {
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
