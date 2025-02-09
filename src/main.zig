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

const screen_w = 1920;
const screen_h = 1080;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    // =========================== Initialize OpenGL + GLFW ===========================
    std.debug.print("Setting up OpenGL context...\n", .{});
    var context = try core.Context.init(allocator, screen_w, screen_h, true, true, true);
    defer context.destroy(allocator);
    var ticker = try core.Ticker.init();
    var camera = scene.Camera{ .translation = zm.Vec3f{ 0, 0, -3 }, .ticker = &ticker };
    var input_handler = scene.InputHandler.init(&camera);

    context.window.setUserPointer(&input_handler);
    context.window.setCursorPosCallback(struct {
        fn anonymous_callback(window: glfw.Window, x: f64, y: f64) void {
            const user_ptr = window.getUserPointer(scene.InputHandler);
            if (user_ptr != null) {
                user_ptr.?.mouseCallback(x, y);
            }
        }
    }.anonymous_callback);
    context.window.setKeyCallback(struct {
        fn anonymous_callback(window: glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: glfw.Mods) void {
            const user_ptr = window.getUserPointer(scene.InputHandler);
            if (user_ptr != null) {
                user_ptr.?.keyCallback(window, key, scancode, action, mods);
            }
        }
    }.anonymous_callback);
    // ===================================================================================
    // ===================================== Shaders =====================================
    std.debug.print("Loading shaders...\n", .{});
    const light_shader_program: core.ShaderProgram = try core.ShaderProgram.init(
        allocator,
        "shaders/vertex_shader_light.glsl",
        "shaders/fragment_shader_light.glsl",
    );
    defer light_shader_program.delete();
    const textured_shader_program: core.ShaderProgram = try core.ShaderProgram.init(
        allocator,
        "shaders/vertex_shader_light_textured.glsl",
        "shaders/fragment_shader_pointlight_textured.glsl",
    );
    defer textured_shader_program.delete();
    const spotlight_textured_shader_program: core.ShaderProgram = try core.ShaderProgram.init(
        allocator,
        "shaders/vertex_shader_light_textured.glsl",
        "shaders/fragment_shader_spotlight_textured.glsl",
    );
    defer spotlight_textured_shader_program.delete();
    const multilight_textured_shader_program: core.ShaderProgram = try core.ShaderProgram.init(
        allocator,
        "shaders/vertex_shader_light_textured.glsl",
        "shaders/fragment_shader_multilight_textured.glsl",
    );
    defer multilight_textured_shader_program.delete();
    const skybox_shader_program: core.ShaderProgram = try core.ShaderProgram.init(
        allocator,
        "shaders/vertex_shader_skybox.glsl",
        "shaders/fragment_shader_skybox.glsl",
    );
    defer skybox_shader_program.delete();
    // ===================================================================================
    // ============================ VBOS, VAOs, and VEOs =================================
    std.debug.print("Loading assets...\n", .{});
    std.debug.print("\t[*] Vertex data...\n", .{});
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
    const cube_vertices = [_]gl.float{
        // positions   texture coords   normal coords
        -0.5, -0.5, -0.5,  0.0, 0.0,  0.0,  0.0, -1.0,
         0.5, -0.5, -0.5,  1.0, 0.0,  0.0,  0.0, -1.0,
         0.5,  0.5, -0.5,  1.0, 1.0,  0.0,  0.0, -1.0,
         0.5,  0.5, -0.5,  1.0, 1.0,  0.0,  0.0, -1.0,
        -0.5,  0.5, -0.5,  0.0, 1.0,  0.0,  0.0, -1.0,
        -0.5, -0.5, -0.5,  0.0, 0.0,  0.0,  0.0, -1.0,
                                                      
        -0.5, -0.5,  0.5,  0.0, 0.0,  0.0,  0.0,  1.0,
         0.5, -0.5,  0.5,  1.0, 0.0,  0.0,  0.0,  1.0,
         0.5,  0.5,  0.5,  1.0, 1.0,  0.0,  0.0,  1.0,
         0.5,  0.5,  0.5,  1.0, 1.0,  0.0,  0.0,  1.0,
        -0.5,  0.5,  0.5,  0.0, 1.0,  0.0,  0.0,  1.0,
        -0.5, -0.5,  0.5,  0.0, 0.0,  0.0,  0.0,  1.0,
                                                      
        -0.5,  0.5,  0.5,  1.0, 0.0, -1.0,  0.0,  0.0,
        -0.5,  0.5, -0.5,  1.0, 1.0, -1.0,  0.0,  0.0,
        -0.5, -0.5, -0.5,  0.0, 1.0, -1.0,  0.0,  0.0,
        -0.5, -0.5, -0.5,  0.0, 1.0, -1.0,  0.0,  0.0,
        -0.5, -0.5,  0.5,  0.0, 0.0, -1.0,  0.0,  0.0,
        -0.5,  0.5,  0.5,  1.0, 0.0, -1.0,  0.0,  0.0,
                                                      
         0.5,  0.5,  0.5,  1.0, 0.0,  1.0,  0.0,  0.0,
         0.5,  0.5, -0.5,  1.0, 1.0,  1.0,  0.0,  0.0,
         0.5, -0.5, -0.5,  0.0, 1.0,  1.0,  0.0,  0.0,
         0.5, -0.5, -0.5,  0.0, 1.0,  1.0,  0.0,  0.0,
         0.5, -0.5,  0.5,  0.0, 0.0,  1.0,  0.0,  0.0,
         0.5,  0.5,  0.5,  1.0, 0.0,  1.0,  0.0,  0.0,
                                                      
        -0.5, -0.5, -0.5,  0.0, 1.0,  0.0, -1.0,  0.0,
         0.5, -0.5, -0.5,  1.0, 1.0,  0.0, -1.0,  0.0,
         0.5, -0.5,  0.5,  1.0, 0.0,  0.0, -1.0,  0.0,
         0.5, -0.5,  0.5,  1.0, 0.0,  0.0, -1.0,  0.0,
        -0.5, -0.5,  0.5,  0.0, 0.0,  0.0, -1.0,  0.0,
        -0.5, -0.5, -0.5,  0.0, 1.0,  0.0, -1.0,  0.0,
                                                      
        -0.5,  0.5, -0.5,  0.0, 1.0,  0.0,  1.0,  0.0,
         0.5,  0.5, -0.5,  1.0, 1.0,  0.0,  1.0,  0.0,
         0.5,  0.5,  0.5,  1.0, 0.0,  0.0,  1.0,  0.0,
         0.5,  0.5,  0.5,  1.0, 0.0,  0.0,  1.0,  0.0,
        -0.5,  0.5,  0.5,  0.0, 0.0,  0.0,  1.0,  0.0,
        -0.5,  0.5, -0.5,  0.0, 1.0,  0.0,  1.0,  0.0,
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
    defer gl.DeleteTextures(3, &TBOs);
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
    gl.BufferData(gl.ARRAY_BUFFER, @sizeOf(gl.float) * cube_vertices.len, &cube_vertices, gl.STATIC_DRAW);
    gl.VertexAttribPointer(index, size, type_, normalized, 8 * @sizeOf(gl.float), pos_pointer);
    gl.EnableVertexAttribArray(index);
    gl.VertexAttribPointer(1, 2, type_, normalized, 8 * @sizeOf(gl.float), 3 * @sizeOf(gl.float));
    gl.EnableVertexAttribArray(1);
    gl.VertexAttribPointer(2, 3, type_, normalized, 8*@sizeOf(gl.float), 5 * @sizeOf(gl.float));
    gl.EnableVertexAttribArray(2);
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
    std.debug.print("\t[*] Texture data...\n", .{});
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
    var image: zigimg.Image = try zigimg.Image.fromFilePath(allocator, "textures/container.png");
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
    image = try zigimg.Image.fromFilePath(allocator, "textures/container_specular.png");
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
    // try textured_shader_program.setInt("u_material.diffuse", 0);
    // try textured_shader_program.setInt("u_material.specular", 1);

    std.debug.print("\t[*] Skybox data...\n", .{});
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
    gl.BindBuffer(gl.ARRAY_BUFFER, light_cube_vbo); // FIXME: There's no need for a dedicaterd VBO, we can reuse the previous cube's
    defer gl.BindBuffer(gl.ARRAY_BUFFER, 0);
    gl.BufferData(gl.ARRAY_BUFFER, @sizeOf(gl.float) * cube_vertices.len, &cube_vertices, gl.STATIC_DRAW);
    gl.VertexAttribPointer(index, size, type_, normalized, 8 * @sizeOf(gl.float), pos_pointer);
    gl.EnableVertexAttribArray(index);
    
    // ===================================================================================
    std.debug.print("Moving things around...\n", .{});
    gl.ClearColor(0.0, 0.0, 0.0, 1);
    var active_shader_program: core.ShaderProgram = textured_shader_program;
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

    const point_lights = [_]zm.Vec3f{
        zm.Vec3f{0.7, 0.2, 2.0},
        zm.Vec3f{2.3, -3.3, -4.0},
        zm.Vec3f{-4.0, 2.0, -12.0},
        zm.Vec3f{0.0, 0.0, -3.0},
    };
    std.debug.print("Done!\n", .{});

    // Wait for the user to close the window. This is the render loop!
    while (!context.window.shouldClose()) {
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT); // Clear the color and z buffers
        input_handler.consume(context.window);
        ticker.tick();

        scene_switch: switch(input_handler.scene) {
            .skybox => {
                gl.DepthFunc(gl.LEQUAL); // Change depth function so depth test passes when values are equal to depth buffer's content
                // gl.DepthMask(gl.FALSE); // Disable depth writing so we don't need to worry about
                // the scale of the skybox!
                skybox_shader_program.use();
                try skybox_shader_program.setMat4f("u_view", camera.getSkyboxViewMat(), true);
                // try skybox_shader_program.setMat4f("u_view", zm.Mat4f.identity(), true);
                try skybox_shader_program.setMat4f("u_proj", projection_mat, true);
                gl.BindVertexArray(skybox_vao);
                gl.DrawArrays(gl.TRIANGLES, 0, 36);
                // gl.DepthMask(gl.TRUE);
                gl.DepthFunc(gl.LESS); // Set depth function back to default
                continue :scene_switch scene.InputHandler.Scene.no_skybox_textured;
            },
            .no_skybox_raw => {
                light_shader_program.use();
                active_shader_program = light_shader_program;
                // try active_shader_program.setBool("u_is_source", true);
                try active_shader_program.setMat4f("u_view", camera.getViewMat(), true);
                try active_shader_program.setMat4f("u_proj", projection_mat, true);
                try active_shader_program.setMat4f("u_model", zm.Mat4f.scaling(0.3, 0.3, 0.3), true,); 
                try active_shader_program.setVec3f("u_cam_pos", camera.translation);
                try active_shader_program.setDirectionalLight(.{
                    .direction = zm.Vec3f{-0.2, -1.0, -0.3},
                    .ambient = zm.Vec3f{0.2, 0.2, 0.2},
                    .diffuse = zm.Vec3f{0.5, 0.5, 0.5},
                    .specular = zm.Vec3f{1.0, 1.0, 1.0},
                });
                try active_shader_program.setMaterial(.{
                    .ambient = zm.Vec3f{0.1, 0.6, 0.05},
                    .diffuse = zm.Vec3f{0.1, 0.6, 0.05},
                    .specular = zm.Vec3f{0.5, 0.5, 0.05},
                    .shininess = 32,
                });
                // gl.BindVertexArray(light_cube_vao);
                // gl.DrawArrays(gl.TRIANGLES, 0, 36);
                try active_shader_program.setBool("u_is_source", false);
            },
            .no_skybox_textured => {
                textured_shader_program.use();
                active_shader_program = textured_shader_program;
                try active_shader_program.setBool("u_is_source", true);
                try active_shader_program.setMat4f("u_view", camera.getViewMat(), true);
                try active_shader_program.setMat4f("u_proj", projection_mat, true);
                try active_shader_program.setMat4f("u_model", zm.Mat4f.scaling(0.3, 0.3, 0.3), true,); 
                try active_shader_program.setVec3f("u_cam_pos", camera.translation);
                try active_shader_program.setPointLight(null, .{
                    .position = zm.Vec3f{0.0, 0.0, 0.0},
                    .ambient = zm.Vec3f{0.2, 0.2, 0.2},
                    .diffuse = zm.Vec3f{0.5, 0.5, 0.5},
                    .specular = zm.Vec3f{1.0, 1.0, 1.0},
                    .constant = 1.0,
                    .linear = 0.09,
                    .quadratic = 0.032,
                });
                try active_shader_program.setTextureMaterial(.{
                    .diffuse_texture_index = 0,
                    .specular_texture_index = 1,
                    .shininess = 32,
                });
                gl.BindVertexArray(light_cube_vao);
                gl.DrawArrays(gl.TRIANGLES, 0, 36);
                try active_shader_program.setBool("u_is_source", false);
            },
            .no_skybox_textured_spotlight => {
                spotlight_textured_shader_program.use();
                active_shader_program = spotlight_textured_shader_program;
                try active_shader_program.setMat4f("u_view", camera.getViewMat(), true);
                try active_shader_program.setMat4f("u_proj", projection_mat, true);
                try active_shader_program.setMat4f("u_model", zm.Mat4f.scaling(0.3, 0.3, 0.3), true,); 
                try active_shader_program.setVec3f("u_cam_pos", camera.translation);
                try active_shader_program.setSpotLight(.{
                    .position = camera.translation,
                    .direction = camera.front,
                    .inner_cutoff_angle_cosine = @cos(std.math.degreesToRadians(15)),
                    .outer_cutoff_angle_cosine = @cos(std.math.degreesToRadians(25)),
                    .ambient = zm.Vec3f{0.2, 0.2, 0.2},
                    .diffuse = zm.Vec3f{0.7, 0.7, 0.7},
                    .specular = zm.Vec3f{1.0, 1.0, 1.0},
                    .constant = 1.0,
                    .linear = 0.027,
                    .quadratic = 0.0028,
                });
                try active_shader_program.setTextureMaterial(.{
                    .diffuse_texture_index = 0,
                    .specular_texture_index = 1,
                    .shininess = 32,
                });
            },
            .no_skybox_textured_multilight => {
                multilight_textured_shader_program.use();
                active_shader_program = multilight_textured_shader_program;
                try active_shader_program.setBool("u_is_source", true);
                try active_shader_program.setMat4f("u_view", camera.getViewMat(), true);
                try active_shader_program.setMat4f("u_proj", projection_mat, true);
                try active_shader_program.setMat4f("u_model", zm.Mat4f.scaling(0.3, 0.3, 0.3), true,); 
                try active_shader_program.setVec3f("u_cam_pos", camera.translation);
                for (point_lights, 0..) |light_pos, i| {
                    try active_shader_program.setPointLight(@as(u8, @intCast(i)), .{
                        .position = light_pos,
                        .ambient = zm.Vec3f{0.1, 0.1, 0.1},
                        .diffuse = zm.Vec3f{0.3, 0.3, 0.3},
                        .specular = zm.Vec3f{1.0, 1.0, 1.0},
                        .constant = 1.0,
                        .linear = 0.09,
                        .quadratic = 0.032,
                    });
                    gl.BindVertexArray(light_cube_vao);
                    try active_shader_program.setMat4f("u_model", zm.Mat4f.translationVec3(light_pos), true,); 
                    gl.DrawArrays(gl.TRIANGLES, 0, 36);
                }
                try active_shader_program.setSpotLight(.{
                    .position = camera.translation,
                    .direction = camera.front,
                    .inner_cutoff_angle_cosine = @cos(std.math.degreesToRadians(15)),
                    .outer_cutoff_angle_cosine = @cos(std.math.degreesToRadians(25)),
                    .ambient = zm.Vec3f{0.1, 0.1, 0.1},
                    .diffuse = zm.Vec3f{0.9, 0.0, 0.0},
                    .specular = zm.Vec3f{1.0, 0.0, 0.0},
                    .constant = 1.0,
                    .linear = 0.027,
                    .quadratic = 0.0028,
                });
                try active_shader_program.setDirectionalLight(.{
                    .direction = zm.Vec3f{-0.2, -6.0, -2.3},
                    .ambient = zm.Vec3f{0.1, 0.1, 0.1},
                    .diffuse = zm.Vec3f{0.2, 0.2, 0.2},
                    .specular = zm.Vec3f{1.0, 1.0, 1.0},
                });
                try active_shader_program.setTextureMaterial(.{
                    .diffuse_texture_index = 0,
                    .specular_texture_index = 1,
                    .shininess = 32,
                });
                try active_shader_program.setBool("u_is_source", false);
            }
        }

        // we need to transpose to go column-major (OpenGL) since zm is
        // row-major.
        try active_shader_program.setMat4f("u_view", camera.getViewMat(), true);
        try active_shader_program.setMat4f("u_proj", projection_mat, true);
        gl.BindVertexArray(cube_vao);
        for (cube_transforms) |cube_transform| {
            try active_shader_program.setMat4f("u_model", cube_transform, true,); 
            gl.DrawArrays(gl.TRIANGLES, 0, 36);
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
