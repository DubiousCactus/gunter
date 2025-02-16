const std = @import("std");
const gl = @import("gl");
const zigimg = @import("zigimg");
const zm = @import("zm");

const gl_log = std.log.scoped(.gl);
const log = std.log;

pub const TextureType = enum {
    diffuse,
    specular,
    base_color,
    metalic_roughness,
};

pub const Texture = struct {
    id: u8,
    type_: TextureType,
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
