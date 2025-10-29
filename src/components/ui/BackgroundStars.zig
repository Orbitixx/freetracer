const rl = @import("raylib");

const ResourceImport = @import("../../managers/ResourceManager.zig");
const ResourceManager = ResourceImport.ResourceManagerSingleton;
const TextureResource = ResourceImport.TEXTURE;

const WindowManager = @import("../../managers/WindowManager.zig").WindowManagerSingleton;

pub fn draw() void {
    const width = WindowManager.getWindowWidth();
    const height = WindowManager.getWindowHeight();

    if (width <= 0 or height <= 0) return;

    var centers: [StarDefinitions.len]rl.Vector2 = undefined;

    for (StarDefinitions, 0..) |def, idx| {
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

    for (Constellations) |constellation| {
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

fn makeStar(anchor: rl.Vector2, baseScale: f32, spread: rl.Vector2, seed: usize) StarDefinition {
    const tex = if (((seed * 13) + 7) % 9 == 0) TextureResource.STAR_V2 else TextureResource.STAR_V1;
    const offset = rl.Vector2{
        .x = pseudoNoise(seed + 5) * spread.x,
        .y = pseudoNoise(seed + 11) * spread.y,
    };

    const scale = baseScale + pseudoNoise(seed + 23) * 0.15;

    return .{
        .texture = tex,
        .anchor = anchor,
        .offset = offset,
        .scale = @max(0.42, scale),
        .rotation = 0,
        .tint = rl.Color.white,
    };
}

const StarSeed = struct {
    anchor: rl.Vector2,
    baseScale: f32,
    spread: rl.Vector2,
    seed: usize,
};

const StarSeedData = [_]StarSeed{
    .{ .anchor = .{ .x = 0.08, .y = 0.10 }, .baseScale = 0.55, .spread = .{ .x = 22, .y = 12 }, .seed = 3 },
    .{ .anchor = .{ .x = 0.16, .y = 0.115 }, .baseScale = 0.55, .spread = .{ .x = 22, .y = 12 }, .seed = 4 },
    .{ .anchor = .{ .x = 0.25, .y = 0.08 }, .baseScale = 0.55, .spread = .{ .x = 22, .y = 12 }, .seed = 5 },
    .{ .anchor = .{ .x = 0.34, .y = 0.115 }, .baseScale = 0.55, .spread = .{ .x = 22, .y = 12 }, .seed = 6 },
    .{ .anchor = .{ .x = 0.48, .y = 0.10 }, .baseScale = 0.55, .spread = .{ .x = 22, .y = 12 }, .seed = 7 },
    .{ .anchor = .{ .x = 0.62, .y = 0.115 }, .baseScale = 0.55, .spread = .{ .x = 22, .y = 12 }, .seed = 8 },
    .{ .anchor = .{ .x = 0.78, .y = 0.10 }, .baseScale = 0.55, .spread = .{ .x = 22, .y = 12 }, .seed = 9 },
    .{ .anchor = .{ .x = 0.14, .y = 0.88 }, .baseScale = 0.57, .spread = .{ .x = 20, .y = 14 }, .seed = 24 },
    .{ .anchor = .{ .x = 0.24, .y = 0.862 }, .baseScale = 0.57, .spread = .{ .x = 20, .y = 14 }, .seed = 25 },
    .{ .anchor = .{ .x = 0.34, .y = 0.88 }, .baseScale = 0.57, .spread = .{ .x = 20, .y = 14 }, .seed = 26 },
    .{ .anchor = .{ .x = 0.46, .y = 0.862 }, .baseScale = 0.57, .spread = .{ .x = 20, .y = 14 }, .seed = 27 },
    .{ .anchor = .{ .x = 0.58, .y = 0.88 }, .baseScale = 0.57, .spread = .{ .x = 20, .y = 14 }, .seed = 28 },
    .{ .anchor = .{ .x = 0.70, .y = 0.862 }, .baseScale = 0.57, .spread = .{ .x = 20, .y = 14 }, .seed = 29 },
    .{ .anchor = .{ .x = 0.07, .y = 0.26 }, .baseScale = 0.60, .spread = .{ .x = 14, .y = 18 }, .seed = 42 },
    .{ .anchor = .{ .x = 0.082, .y = 0.34 }, .baseScale = 0.60, .spread = .{ .x = 14, .y = 18 }, .seed = 43 },
    .{ .anchor = .{ .x = 0.07, .y = 0.42 }, .baseScale = 0.60, .spread = .{ .x = 14, .y = 18 }, .seed = 44 },
    .{ .anchor = .{ .x = 0.082, .y = 0.58 }, .baseScale = 0.60, .spread = .{ .x = 14, .y = 18 }, .seed = 45 },
    .{ .anchor = .{ .x = 0.93, .y = 0.20 }, .baseScale = 0.58, .spread = .{ .x = 16, .y = 18 }, .seed = 58 },
    .{ .anchor = .{ .x = 0.918, .y = 0.30 }, .baseScale = 0.58, .spread = .{ .x = 16, .y = 18 }, .seed = 59 },
    .{ .anchor = .{ .x = 0.93, .y = 0.44 }, .baseScale = 0.58, .spread = .{ .x = 16, .y = 18 }, .seed = 60 },
    .{ .anchor = .{ .x = 0.918, .y = 0.58 }, .baseScale = 0.58, .spread = .{ .x = 16, .y = 18 }, .seed = 61 },
    .{ .anchor = .{ .x = 0.42, .y = 0.46 }, .baseScale = 0.50, .spread = .{ .x = 26, .y = 22 }, .seed = 74 },
    .{ .anchor = .{ .x = 0.52, .y = 0.52 }, .baseScale = 0.50, .spread = .{ .x = 26, .y = 22 }, .seed = 76 },
    .{ .anchor = .{ .x = 0.46, .y = 0.64 }, .baseScale = 0.50, .spread = .{ .x = 26, .y = 22 }, .seed = 78 },
    .{ .anchor = .{ .x = 0.58, .y = 0.68 }, .baseScale = 0.50, .spread = .{ .x = 26, .y = 22 }, .seed = 80 },
    .{ .anchor = .{ .x = 0.04, .y = 0.08 }, .baseScale = 0.41, .spread = .{ .x = 14, .y = 10 }, .seed = 86 },
    .{ .anchor = .{ .x = 0.92, .y = 0.07 }, .baseScale = 0.41, .spread = .{ .x = 14, .y = 10 }, .seed = 88 },
    .{ .anchor = .{ .x = 0.05, .y = 0.26 }, .baseScale = 0.41, .spread = .{ .x = 16, .y = 14 }, .seed = 90 },
    .{ .anchor = .{ .x = 0.95, .y = 0.27 }, .baseScale = 0.42, .spread = .{ .x = 16, .y = 14 }, .seed = 92 },
    .{ .anchor = .{ .x = 0.03, .y = 0.50 }, .baseScale = 0.40, .spread = .{ .x = 18, .y = 16 }, .seed = 94 },
    .{ .anchor = .{ .x = 0.97, .y = 0.52 }, .baseScale = 0.41, .spread = .{ .x = 18, .y = 16 }, .seed = 96 },
    .{ .anchor = .{ .x = 0.07, .y = 0.70 }, .baseScale = 0.41, .spread = .{ .x = 18, .y = 18 }, .seed = 98 },
    .{ .anchor = .{ .x = 0.93, .y = 0.72 }, .baseScale = 0.42, .spread = .{ .x = 18, .y = 18 }, .seed = 100 },
    .{ .anchor = .{ .x = 0.06, .y = 0.93 }, .baseScale = 0.43, .spread = .{ .x = 20, .y = 20 }, .seed = 102 },
    .{ .anchor = .{ .x = 0.94, .y = 0.92 }, .baseScale = 0.44, .spread = .{ .x = 20, .y = 20 }, .seed = 104 },
    .{ .anchor = .{ .x = 0.12, .y = 0.18 }, .baseScale = 0.46, .spread = .{ .x = 18, .y = 14 }, .seed = 106 },
    .{ .anchor = .{ .x = 0.30, .y = 0.19 }, .baseScale = 0.44, .spread = .{ .x = 18, .y = 16 }, .seed = 108 },
    .{ .anchor = .{ .x = 0.48, .y = 0.18 }, .baseScale = 0.45, .spread = .{ .x = 20, .y = 14 }, .seed = 110 },
    .{ .anchor = .{ .x = 0.66, .y = 0.17 }, .baseScale = 0.43, .spread = .{ .x = 18, .y = 14 }, .seed = 112 },
    .{ .anchor = .{ .x = 0.84, .y = 0.19 }, .baseScale = 0.44, .spread = .{ .x = 18, .y = 14 }, .seed = 114 },
    .{ .anchor = .{ .x = 0.18, .y = 0.40 }, .baseScale = 0.43, .spread = .{ .x = 22, .y = 18 }, .seed = 116 },
    .{ .anchor = .{ .x = 0.38, .y = 0.42 }, .baseScale = 0.45, .spread = .{ .x = 22, .y = 18 }, .seed = 118 },
    .{ .anchor = .{ .x = 0.58, .y = 0.41 }, .baseScale = 0.44, .spread = .{ .x = 22, .y = 18 }, .seed = 120 },
    .{ .anchor = .{ .x = 0.78, .y = 0.43 }, .baseScale = 0.43, .spread = .{ .x = 22, .y = 18 }, .seed = 122 },
    .{ .anchor = .{ .x = 0.14, .y = 0.56 }, .baseScale = 0.42, .spread = .{ .x = 24, .y = 20 }, .seed = 124 },
    .{ .anchor = .{ .x = 0.34, .y = 0.58 }, .baseScale = 0.44, .spread = .{ .x = 24, .y = 20 }, .seed = 126 },
    .{ .anchor = .{ .x = 0.54, .y = 0.57 }, .baseScale = 0.43, .spread = .{ .x = 24, .y = 20 }, .seed = 128 },
    .{ .anchor = .{ .x = 0.74, .y = 0.59 }, .baseScale = 0.42, .spread = .{ .x = 24, .y = 20 }, .seed = 130 },
    .{ .anchor = .{ .x = 0.24, .y = 0.72 }, .baseScale = 0.43, .spread = .{ .x = 26, .y = 22 }, .seed = 132 },
    .{ .anchor = .{ .x = 0.44, .y = 0.71 }, .baseScale = 0.45, .spread = .{ .x = 26, .y = 22 }, .seed = 134 },
    .{ .anchor = .{ .x = 0.64, .y = 0.73 }, .baseScale = 0.43, .spread = .{ .x = 26, .y = 22 }, .seed = 136 },
    .{ .anchor = .{ .x = 0.84, .y = 0.74 }, .baseScale = 0.42, .spread = .{ .x = 26, .y = 22 }, .seed = 138 },
    .{ .anchor = .{ .x = 0.18, .y = 0.86 }, .baseScale = 0.44, .spread = .{ .x = 28, .y = 24 }, .seed = 140 },
    .{ .anchor = .{ .x = 0.38, .y = 0.87 }, .baseScale = 0.46, .spread = .{ .x = 28, .y = 24 }, .seed = 142 },
    .{ .anchor = .{ .x = 0.58, .y = 0.85 }, .baseScale = 0.44, .spread = .{ .x = 28, .y = 24 }, .seed = 144 },
    .{ .anchor = .{ .x = 0.78, .y = 0.88 }, .baseScale = 0.43, .spread = .{ .x = 28, .y = 24 }, .seed = 146 },
};

const StarCount = StarSeedData.len;

fn generateStars() [StarCount]StarDefinition {
    var stars: [StarCount]StarDefinition = undefined;

    inline for (StarSeedData, 0..) |data, idx| {
        stars[idx] = makeStar(data.anchor, data.baseScale, data.spread, data.seed);
    }

    return stars;
}

const StarDefinitions = generateStars();

const ConstellationTop = [_]usize{ 1, 2, 3 };
const ConstellationUpper = [_]usize{ 4, 5 };
const ConstellationLeft = [_]usize{ 13, 14, 15 };
const ConstellationLower = [_]usize{ 9, 10, 11 };
const ConstellationRibbon = [_]usize{ 17, 18, 19, 20 };

const Constellations = [_]Constellation{
    .{ .indices = &ConstellationTop, .color = rl.Color.init(140, 190, 255, 95), .thickness = 1.0 },
    .{ .indices = &ConstellationUpper, .color = rl.Color.init(150, 205, 255, 85), .thickness = 1.0 },
    .{ .indices = &ConstellationLeft, .color = rl.Color.init(135, 185, 250, 90), .thickness = 1.1 },
    .{ .indices = &ConstellationLower, .color = rl.Color.init(150, 210, 255, 80), .thickness = 1.0 },
    .{ .indices = &ConstellationRibbon, .color = rl.Color.init(110, 170, 245, 70), .thickness = 1.2 },
};
