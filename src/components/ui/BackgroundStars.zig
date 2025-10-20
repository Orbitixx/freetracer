const rl = @import("raylib");

const ResourceImport = @import("../../managers/ResourceManager.zig");
const ResourceManager = ResourceImport.ResourceManagerSingleton;
const TextureResource = ResourceImport.TEXTURE;

const WindowManager = @import("../../managers/WindowManager.zig").WindowManagerSingleton;

pub fn draw() void {
    const width = WindowManager.getWindowWidth();
    const height = WindowManager.getWindowHeight();

    if (width <= 0 or height <= 0) return;

    var centers: [star_definitions.len]rl.Vector2 = undefined;

    for (star_definitions, 0..) |def, idx| {
        const texture = ResourceManager.getTexture(def.texture);
        const textureWidth = @as(f32, @floatFromInt(texture.width)) * def.scale;
        const textureHeight = @as(f32, @floatFromInt(texture.height)) * def.scale;

        const position = rl.Vector2{
            .x = def.anchor.x * width + def.offset.x,
            .y = def.anchor.y * height + def.offset.y,
        };

        rl.drawTextureEx(texture, position, def.rotation, def.scale, def.tint);

        centers[idx] = .{
            .x = position.x + textureWidth / 2,
            .y = position.y + textureHeight / 2,
        };
    }

    for (constellations) |constellation| {
        if (constellation.indices.len < 2) continue;

        var previous = centers[constellation.indices[0]];
        for (constellation.indices[1..]) |idx| {
            const current = centers[idx];
            rl.drawLineEx(previous, current, constellation.thickness, constellation.color);
            previous = current;
        }
    }
}

const StarDefinition = struct {
    texture: TextureResource,
    anchor: rl.Vector2,
    offset: rl.Vector2 = rl.Vector2{ .x = 0, .y = 0 },
    scale: f32,
    rotation: f32 = 0,
    tint: rl.Color,
};

const Constellation = struct {
    indices: []const usize,
    color: rl.Color,
    thickness: f32,
};

fn pseudoNoise(seed: usize) f32 {
    const mixed = (seed * 1103515245 + 12345) & 0xffff;
    return (@as(f32, @floatFromInt(mixed)) / 32768.0) * 2.0 - 1.0;
}

fn makeStar(anchor: rl.Vector2, base_scale: f32, spread: rl.Vector2, seed: usize) StarDefinition {
    const tex = if (((seed * 13) + 7) % 9 == 0) TextureResource.STAR_V2 else TextureResource.STAR_V1;
    const offset = rl.Vector2{
        .x = pseudoNoise(seed + 5) * spread.x,
        .y = pseudoNoise(seed + 11) * spread.y,
    };

    const scale = base_scale + pseudoNoise(seed + 23) * 0.15;
    // const rotation = pseudoNoise(seed + 31) * 14.0;

    // const alpha: u8 = @intCast(190 + ((seed * 19) % 50));
    // const r: u8 = @intCast(235 + ((seed * 7) % 20));
    // const g = @intCast(240 + ((seed * 9) % 15));

    return .{
        .texture = tex,
        .anchor = anchor,
        .offset = offset,
        .scale = @max(0.42, scale),
        .rotation = 0,
        .tint = rl.Color.white,
    };
}

const top_positions = [_]f32{ 0.08, 0.16, 0.24, 0.34, 0.48, 0.62, 0.78 };
const bottom_positions = [_]f32{ 0.14, 0.24, 0.34, 0.46, 0.58, 0.70 };
const left_positions = [_]f32{ 0.26, 0.34, 0.42, 0.58 };
const right_positions = [_]f32{ 0.20, 0.30, 0.44, 0.58 };
const inner_positions = [_]rl.Vector2{
    .{ .x = 0.42, .y = 0.46 },
    .{ .x = 0.52, .y = 0.52 },
    .{ .x = 0.46, .y = 0.64 },
    .{ .x = 0.58, .y = 0.68 },
};

const extra_positions = [_]struct {
    anchor: rl.Vector2,
    base_scale: f32,
    spread: rl.Vector2,
}{
    .{ .anchor = .{ .x = 0.04, .y = 0.08 }, .base_scale = 0.41, .spread = .{ .x = 14, .y = 10 } },
    .{ .anchor = .{ .x = 0.92, .y = 0.07 }, .base_scale = 0.41, .spread = .{ .x = 14, .y = 10 } },
    .{ .anchor = .{ .x = 0.05, .y = 0.26 }, .base_scale = 0.41, .spread = .{ .x = 16, .y = 14 } },
    .{ .anchor = .{ .x = 0.95, .y = 0.27 }, .base_scale = 0.42, .spread = .{ .x = 16, .y = 14 } },
    .{ .anchor = .{ .x = 0.03, .y = 0.50 }, .base_scale = 0.40, .spread = .{ .x = 18, .y = 16 } },
    .{ .anchor = .{ .x = 0.97, .y = 0.52 }, .base_scale = 0.41, .spread = .{ .x = 18, .y = 16 } },
    .{ .anchor = .{ .x = 0.07, .y = 0.70 }, .base_scale = 0.41, .spread = .{ .x = 18, .y = 18 } },
    .{ .anchor = .{ .x = 0.93, .y = 0.72 }, .base_scale = 0.42, .spread = .{ .x = 18, .y = 18 } },
    .{ .anchor = .{ .x = 0.06, .y = 0.93 }, .base_scale = 0.43, .spread = .{ .x = 20, .y = 20 } },
    .{ .anchor = .{ .x = 0.94, .y = 0.92 }, .base_scale = 0.44, .spread = .{ .x = 20, .y = 20 } },
    .{ .anchor = .{ .x = 0.12, .y = 0.18 }, .base_scale = 0.46, .spread = .{ .x = 18, .y = 14 } },
    .{ .anchor = .{ .x = 0.30, .y = 0.19 }, .base_scale = 0.44, .spread = .{ .x = 18, .y = 16 } },
    .{ .anchor = .{ .x = 0.48, .y = 0.18 }, .base_scale = 0.45, .spread = .{ .x = 20, .y = 14 } },
    .{ .anchor = .{ .x = 0.66, .y = 0.17 }, .base_scale = 0.43, .spread = .{ .x = 18, .y = 14 } },
    .{ .anchor = .{ .x = 0.84, .y = 0.19 }, .base_scale = 0.44, .spread = .{ .x = 18, .y = 14 } },
    .{ .anchor = .{ .x = 0.18, .y = 0.40 }, .base_scale = 0.43, .spread = .{ .x = 22, .y = 18 } },
    .{ .anchor = .{ .x = 0.38, .y = 0.42 }, .base_scale = 0.45, .spread = .{ .x = 22, .y = 18 } },
    .{ .anchor = .{ .x = 0.58, .y = 0.41 }, .base_scale = 0.44, .spread = .{ .x = 22, .y = 18 } },
    .{ .anchor = .{ .x = 0.78, .y = 0.43 }, .base_scale = 0.43, .spread = .{ .x = 22, .y = 18 } },
    .{ .anchor = .{ .x = 0.14, .y = 0.56 }, .base_scale = 0.42, .spread = .{ .x = 24, .y = 20 } },
    .{ .anchor = .{ .x = 0.34, .y = 0.58 }, .base_scale = 0.44, .spread = .{ .x = 24, .y = 20 } },
    .{ .anchor = .{ .x = 0.54, .y = 0.57 }, .base_scale = 0.43, .spread = .{ .x = 24, .y = 20 } },
    .{ .anchor = .{ .x = 0.74, .y = 0.59 }, .base_scale = 0.42, .spread = .{ .x = 24, .y = 20 } },
    .{ .anchor = .{ .x = 0.24, .y = 0.72 }, .base_scale = 0.43, .spread = .{ .x = 26, .y = 22 } },
    .{ .anchor = .{ .x = 0.44, .y = 0.71 }, .base_scale = 0.45, .spread = .{ .x = 26, .y = 22 } },
    .{ .anchor = .{ .x = 0.64, .y = 0.73 }, .base_scale = 0.43, .spread = .{ .x = 26, .y = 22 } },
    .{ .anchor = .{ .x = 0.84, .y = 0.74 }, .base_scale = 0.42, .spread = .{ .x = 26, .y = 22 } },
    .{ .anchor = .{ .x = 0.18, .y = 0.86 }, .base_scale = 0.44, .spread = .{ .x = 28, .y = 24 } },
    .{ .anchor = .{ .x = 0.38, .y = 0.87 }, .base_scale = 0.46, .spread = .{ .x = 28, .y = 24 } },
    .{ .anchor = .{ .x = 0.58, .y = 0.85 }, .base_scale = 0.44, .spread = .{ .x = 28, .y = 24 } },
    .{ .anchor = .{ .x = 0.78, .y = 0.88 }, .base_scale = 0.43, .spread = .{ .x = 28, .y = 24 } },
};

const STAR_COUNT = top_positions.len
    + bottom_positions.len
    + left_positions.len
    + right_positions.len
    + inner_positions.len
    + extra_positions.len;

fn generateStars() [STAR_COUNT]StarDefinition {
    var stars: [STAR_COUNT]StarDefinition = undefined;
    var idx: usize = 0;

    inline for (top_positions, 0..) |x, top_idx| {
        const y = 0.10 + 0.015 * @as(f32, @floatFromInt(top_idx % 2));
        stars[idx] = makeStar(.{ .x = x, .y = y }, 0.55, .{ .x = 22, .y = 12 }, idx + 3);
        idx += 1;
    }

    inline for (bottom_positions, 0..) |x, bottom_idx| {
        const y = 0.88 - 0.018 * @as(f32, @floatFromInt(bottom_idx % 2));
        stars[idx] = makeStar(.{ .x = x, .y = y }, 0.57, .{ .x = 20, .y = 14 }, idx + 17);
        idx += 1;
    }

    inline for (left_positions, 0..) |y, left_idx| {
        const x = 0.07 + 0.012 * @as(f32, @floatFromInt(left_idx % 2));
        stars[idx] = makeStar(.{ .x = x, .y = y }, 0.6, .{ .x = 14, .y = 18 }, idx + 29);
        idx += 1;
    }

    inline for (right_positions, 0..) |y, right_idx| {
        const x = 0.93 - 0.012 * @as(f32, @floatFromInt(right_idx % 2));
        stars[idx] = makeStar(.{ .x = x, .y = y }, 0.58, .{ .x = 16, .y = 18 }, idx + 41);
        idx += 1;
    }

    inline for (inner_positions, 0..) |anchor, inner_idx| {
        stars[idx] = makeStar(anchor, 0.5, .{ .x = 26, .y = 22 }, idx + 53 + inner_idx);
        idx += 1;
    }

    inline for (extra_positions, 0..) |extra, extra_idx| {
        const seed = extra_start + extra_idx + 61;
        stars[idx] = makeStar(extra.anchor, extra.base_scale, extra.spread, seed);
        idx += 1;
    }

    return stars;
}

const star_definitions = generateStars();

const top_start = 0;
const bottom_start = top_start + top_positions.len;
const left_start = bottom_start + bottom_positions.len;
const right_start = left_start + left_positions.len;
const inner_start = right_start + right_positions.len;
const extra_start = inner_start + inner_positions.len;

const constellation_top = [_]usize{ top_start + 1, top_start + 2, top_start + 3 };
const constellation_upper = [_]usize{ top_start + 4, top_start + 5 };
const constellation_left = [_]usize{ left_start + 0, left_start + 1, left_start + 2 };
const constellation_lower = [_]usize{ bottom_start + 2, bottom_start + 3, bottom_start + 4 };
const constellation_ribbon = [_]usize{ right_start + 0, right_start + 1, right_start + 2, right_start + 3 };

const constellations = [_]Constellation{
    .{ .indices = &constellation_top, .color = rl.Color.init(140, 190, 255, 95), .thickness = 1.0 },
    .{ .indices = &constellation_upper, .color = rl.Color.init(150, 205, 255, 85), .thickness = 1.0 },
    .{ .indices = &constellation_left, .color = rl.Color.init(135, 185, 250, 90), .thickness = 1.1 },
    .{ .indices = &constellation_lower, .color = rl.Color.init(150, 210, 255, 80), .thickness = 1.0 },
    .{ .indices = &constellation_ribbon, .color = rl.Color.init(110, 170, 245, 70), .thickness = 1.2 },
};
