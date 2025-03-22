pub const ValidationEntry = struct {
    headerId: u8,
    platformId: u8,
    reserved1: u8,
    reserved2: u8,
    manufacturerDev: [24]u8,
    checksum: [2]u8,
    reserved3: u8,
    reserved4: u8,
};

pub const InitialDefaultEntry = struct {
    bootIndicator: u8,
    bootMedia: u8,
    loadSegment: [2]u8,
    systemType: u8,
    unused1: u8,
    sectorCount: [2]u8,
    loadRba: [4]u8,
    unused2: [20]u8,
};
