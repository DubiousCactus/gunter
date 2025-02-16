const std = @import("std");
const gl = @import("gl");
const zigimg = @import("zigimg");
const zm = @import("zm");
const zmesh = @import("zmesh");

const gl_log = std.log.scoped(.gl);
const log = std.log;

pub const TextureType = enum {
    diffuse,
    specular,
    base_color,
    metalic_roughness,
};

pub const Texture = struct {
    id: c_uint,
    type_: TextureType,
    path: [*:0]const u8,
};

pub const TextureError = error{
    NoImageProvided,
};

pub fn load_from_path(
    file_name: []const u8,
    gl_location: c_uint,
    gl_texture_type: c_uint,
    TBO: c_uint,
    target: c_uint,
    generate_mipmap: bool,
    allocator: std.mem.Allocator,
) !void {
    const file = std.fs.cwd().openFile(file_name, .{}) catch |err| {
        log.err("failed to open texture file: {?s}", .{file_name});
        return err;
    };
    return try Texture.load_from_file(
        file,
        gl_location,
        gl_texture_type,
        TBO,
        target,
        generate_mipmap,
        allocator,
    );
}

pub fn load_from_file(
    file: std.fs.File,
    gl_location: c_uint,
    gl_texture_type: c_uint,
    TBO: c_uint,
    target: c_uint,
    generate_mipmap: bool,
    allocator: std.mem.Allocator,
) !void {
    var image = try zigimg.Image.fromFile(allocator, @constCast(&file));
    errdefer image.deinit();
    gl.ActiveTexture(gl_location);
    gl.BindTexture(gl_texture_type, TBO);
    // TODO: Clarify where it gets bound. in the active texture or in the bound buffer
    // object??
    gl.TexImage2D(
        target,
        0,
        gl.RGB,
        @as(c_int, @intCast(image.width)),
        @as(c_int, @intCast(image.height)),
        0,
        if (image.pixelFormat().isRgba()) gl.RGBA else gl.RGB,
        gl.UNSIGNED_BYTE,
        image.rawBytes().ptr,
    );
    if (generate_mipmap)
        gl.GenerateMipmap(gl.TEXTURE_2D);
    image.deinit();
}

pub fn load_from_gltf(
    tex: *zmesh.io.zcgltf.Texture,
    root_dir: []const u8,
    allocator: std.mem.Allocator,
) !Texture {
    // INFO: A texture has an "image" source and a "sampler".
    if (tex.image == null) {
        log.err("No image provided for texture", .{});
        return TextureError.NoImageProvided;
    }

    var tbo: [1]c_uint = undefined;
    gl.GenTextures(1, &tbo);

    var path: [*:0]const u8 = undefined;

    if (tex.image.?.uri) |image_uri| {
        path = image_uri;
        std.debug.print("Loading texture from uri: {s}\n", .{image_uri});
        const dir = std.fs.cwd().openDir(root_dir, .{}) catch |err| {
            log.err("failed to open directory: {?s}", .{root_dir});
            return err;
        };
        const file = dir.openFile(std.mem.sliceTo(image_uri, 0), .{}) catch |err| {
            log.err("failed to open texture file: {?s}", .{image_uri});
            return err;
        };
        try load_from_file(file, gl.TEXTURE0, gl.TEXTURE_2D, tbo[0], gl.TEXTURE_2D, false, allocator);
    } else if (tex.image.?.buffer_view) |buffer_view| {
        std.debug.print("Loading texture from buffer view\n", .{});
        std.debug.print("Loading {d} bytes\n", .{buffer_view.size});
        return error.NotImplementedError;
        // const image_data: ?[*]u8 = buffer_view.getData();
        // gl.BindTexture(gl.TEXTURE_2D, tbo[0]);
        // gl.TexImage2D(
        //     gl.TEXTURE_2D,
        //     0,
        //     gl.RGB,
        //     @as(c_int, @intCast(image.width)),
        //     @as(c_int, @intCast(image.height)),
        //     0,
        //     if (image.pixelFormat().isRgba()) gl.RGBA else gl.RGB,
        //     gl.UNSIGNED_BYTE,
        //     image_data,
        // );
        // if (generate_mipmap)
        //     gl.GenerateMipmap(gl.TEXTURE_2D);
    } else if (tex.image.?.extras.data) |image_data| {
        std.debug.print("Loading texture from data\n", .{});
        _ = image_data;
    }
    return .{ .id = tbo[0], .path = path, .type_ = undefined };
}
