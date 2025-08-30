const std = @import("std");
const glfw = @import("mach-glfw");
const gl = @import("gl");
const zigimg = @import("zigimg");
const zm = @import("zm");
const zmesh = @import("zmesh");

const glfw_log = std.log.scoped(.glfw);
const gl_log = std.log.scoped(.gl);
const log = std.log;

const core = @import("core.zig");
const scene = @import("scene.zig");
const model = @import("model.zig");
const input = @import("input.zig");

const screen_w = 1920;
const screen_h = 1080;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    // =========================== Initialize OpenGL + GLFW ===========================
    std.debug.print("Setting up OpenGL context...\n", .{});
    var context = try core.Context.init(allocator, .{
        .width = screen_w,
        .height = screen_h,
        .enable_blending = true,
        .enable_depth_testing = true,
        .enable_vsync = true,
        .grab_mouse = true,
    });
    defer context.destroy(allocator);
    var ticker = try core.Ticker.init();
    var camera = scene.Camera.init(
        &ticker,
        zm.Vec3f{ 0, 0, -6 },
        45,
        screen_w,
        screen_h,
        0.1,
        100.0,
    );
    var input_handler = input.InputHandler.init(&camera);

    context.window.setUserPointer(&input_handler);
    context.window.setCursorPosCallback(struct {
        fn anonymous_callback(window: glfw.Window, x: f64, y: f64) void {
            const user_ptr = window.getUserPointer(input.InputHandler);
            if (user_ptr != null) {
                user_ptr.?.mouseCallback(x, y);
            }
        }
    }.anonymous_callback);
    context.window.setKeyCallback(struct {
        fn anonymous_callback(
            window: glfw.Window,
            key: glfw.Key,
            scancode: i32,
            action: glfw.Action,
            mods: glfw.Mods,
        ) void {
            const user_ptr = window.getUserPointer(input.InputHandler);
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
    const highlight_shader_program: core.ShaderProgram = try core.ShaderProgram.init(
        allocator,
        "shaders/vertex_shader.glsl",
        "shaders/fragment_shader_stencil_highlight.glsl",
    );
    defer highlight_shader_program.delete();
    // ===================================================================================
    // ============================ VBOS, VAOs, and VEOs =================================
    // var my_model = try model.Model.init(
    //     "/Users/cactus/Code/learning-opengl/assets/dude.glb",
    //     allocator,
    //     .load_entire_scene,
    // );
    // var backpack = try model.Model.init(
    //     "/Users/cactus/Code/gunter/assets/guitar-backpack/scene.gltf",
    //     allocator,
    //     .load_entire_scene,
    // );
    // backpack.setScale(0.01);
    // defer backpack.deinit(allocator);
    // backpack.world_matrix = zm.Mat4f.translation(0, -1.5, 4);
    var my_scene = try model.Model.init(
        "/Users/cactus/Code/gunter/assets/blender/test_scene.gltf",
        allocator,
        .load_entire_scene,
    );
    if (my_scene.findByName("Suzanne")) |mesh| {
        mesh.setRenderOptions(.{
            .enable_face_culling = true,
            .use_textures = false,
            .highlight = true,
            .highlight_shader = &highlight_shader_program,
        });
    } else |err| {
        std.debug.print("Couldn't find Suzanne mesh in the scene!\n", .{});
        return err;
    }
    if (my_scene.findByName("Cube")) |mesh| {
        mesh.setRenderOptions(.{ .enable_face_culling = true });
    } else |err| {
        std.debug.print("Couldn't find Suzanne mesh in the scene!\n", .{});
        return err;
    }
    defer my_scene.deinit(allocator);
    // var my_model = try model.Model.init(
    //     "/Users/cactus/Code/learning-opengl/assets/thingy/scene.gltf",
    //     allocator,
    //     .load_entire_scene,
    // );
    // var my_model = try model.Model.init(
    //     "/Users/cactus/Code/learning-opengl/assets/vase/scene.gltf",
    //     allocator,
    //     .load_entire_scene,
    // );
    // var my_model = try model.Model.init(
    //     "/Users/cactus/Code/learning-opengl/assets/dog/scene.gltf",
    //     allocator,
    //     .load_entire_scene,
    // );
    // var my_model = try model.Model.init(
    //     "/Users/cactus/Code/learning-opengl/assets/cube/cube.glb",
    //     allocator,
    //     .load_root_mesh_only,
    // );
    // my_model.scale(1);
    std.debug.print("Model loaded! Drawing...\n", .{});

    const point_lights = [_]zm.Vec3f{
        zm.Vec3f{ 0.7, 0.2, 2.0 },
        zm.Vec3f{ 2.3, -3.3, -4.0 },
        zm.Vec3f{ -4.0, 2.0, -12.0 },
        zm.Vec3f{ 0.0, 0.0, -3.0 },
    };
    std.debug.print("Done!\n", .{});

    var cube_model: model.Mesh = model.Primitive.make_cube_mesh();
    defer cube_model.deinit(allocator);

    const skybox = try scene.SkyBox.init(allocator, "textures/skybox");
    defer skybox.deinit();

    gl.ClearColor(0.0, 0.0, 0.0, 1);
    var active_shader_program: core.ShaderProgram = multilight_textured_shader_program;
    // Wait for the user to close the window. This is the render loop!
    while (!context.window.shouldClose()) {
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT | gl.STENCIL_BUFFER_BIT); // Clear the color and z buffers. TODO: Should be in the context if we do more similar stuff
        input_handler.consume(context.window);
        ticker.tick();

        if (input_handler.scene == .skybox) {
            try skybox.draw(camera.getSkyboxViewMat(), camera.projection_mat);
        }

        multilight_textured_shader_program.use();
        active_shader_program = multilight_textured_shader_program;
        // we need to transpose to go column-major (OpenGL) since zm is
        // row-major.
        try active_shader_program.setMat4f("u_view", camera.getViewMat(), true);
        try active_shader_program.setMat4f("u_proj", camera.projection_mat, true);

        try active_shader_program.setBool("u_is_source", true);
        try active_shader_program.setVec3f("u_cam_pos", camera.translation);
        for (point_lights, 0..) |light_pos, i| {
            try active_shader_program.setPointLight(@as(u8, @intCast(i)), .{
                .position = light_pos,
                .ambient = zm.Vec3f{ 0.1, 0.1, 0.1 },
                .diffuse = zm.Vec3f{ 0.3, 0.3, 0.3 },
                .specular = zm.Vec3f{ 1.0, 1.0, 1.0 },
                .constant = 1.0,
                .linear = 0.09,
                .quadratic = 0.032,
            });
            // TODO: Move the cube into a PointLight class? Then we can pass in less
            // parameters and parameterize rendering the cube.
            cube_model.setScale(0.5);
            cube_model.world_matrix = zm.Mat4f.translationVec3(light_pos);
            // cube_model.scale(0.2);
            try cube_model.draw(active_shader_program, .{ .use_textures = false, .enable_face_culling = true });
        }
        try active_shader_program.setSpotLight(.{
            .position = camera.translation,
            .direction = camera.front,
            .inner_cutoff_angle_cosine = @cos(std.math.degreesToRadians(15)),
            .outer_cutoff_angle_cosine = @cos(std.math.degreesToRadians(25)),
            .ambient = zm.Vec3f{ 0.1, 0.1, 0.1 },
            .diffuse = zm.Vec3f{ 1.0, 1.0, 1.0 },
            .specular = zm.Vec3f{ 1.0, 1.0, 1.0 },
            .constant = 1.0,
            .linear = 0.027,
            .quadratic = 0.0028,
        });
        try active_shader_program.setDirectionalLight(.{
            .direction = zm.Vec3f{ -0.2, -6.0, -2.3 },
            .ambient = zm.Vec3f{ 0.1, 0.1, 0.1 },
            .diffuse = zm.Vec3f{ 0.2, 0.2, 0.2 },
            .specular = zm.Vec3f{ 1.0, 1.0, 1.0 },
        });

        try active_shader_program.setBool("u_is_source", false);
        // try my_model.draw(active_shader_program, .{
        //     .highlight = false,
        //     .highlight_shader = &highlight_shader_program,
        // }, camera.getViewMat(), projection_mat);
        try my_scene.draw(active_shader_program, .{
            .highlight = false,
            .highlight_shader = &highlight_shader_program,
            .enable_face_culling = true,
        }, camera.getViewMat(), camera.projection_mat);

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
