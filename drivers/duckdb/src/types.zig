//! Types and errors of evedb (README.md section 7): DuckDB types as Eve types, a cell as a protocol value, and a DuckDB error
//! as an error class with a SQL state.
const std = @import("std");
const c = @import("duckdb_c");

fn t(comptime name: []const u8) c_uint {
    return @field(c, "DUCKDB_TYPE_" ++ name);
}

/// The name of the Eve type that a DuckDB type stands for.
pub fn eveType(ty: c_uint) []const u8 {
    return switch (ty) {
        t("BOOLEAN") => "Logic",
        t("TINYINT"), t("SMALLINT"), t("INTEGER"), t("BIGINT"), t("UTINYINT"), t("USMALLINT"), t("UINTEGER") => "Integer",
        t("UBIGINT") => "Natural",
        t("HUGEINT"), t("UHUGEINT") => "Huge",
        t("FLOAT") => "Float",
        t("DOUBLE") => "Real",
        t("DECIMAL") => "Decimal",
        t("DATE") => "Date",
        t("TIMESTAMP"), t("TIMESTAMP_TZ"), t("TIMESTAMP_S"), t("TIMESTAMP_MS"), t("TIMESTAMP_NS") => "Instant",
        t("BLOB") => "Bytes",
        t("UUID") => "Uuid",
        else => "String",
    };
}

/// The Eve type of a DuckDB type written as a name.
pub fn eveTypeOfName(name: []const u8) []const u8 {
    const cut = std.mem.indexOfScalar(u8, name, '(') orelse name.len;
    const base = std.mem.trim(u8, name[0..cut], " ");
    const table = [_][2][]const u8{
        .{ "BOOLEAN", "Logic" },        .{ "TINYINT", "Integer" },     .{ "SMALLINT", "Integer" },
        .{ "INTEGER", "Integer" },      .{ "BIGINT", "Integer" },      .{ "UTINYINT", "Integer" },
        .{ "USMALLINT", "Integer" },    .{ "UINTEGER", "Integer" },    .{ "UBIGINT", "Natural" },
        .{ "HUGEINT", "Huge" },         .{ "UHUGEINT", "Huge" },       .{ "FLOAT", "Float" },
        .{ "DOUBLE", "Real" },          .{ "DECIMAL", "Decimal" },     .{ "DATE", "Date" },
        .{ "TIMESTAMP", "Instant" },    .{ "TIMESTAMP WITH TIME ZONE", "Instant" }, .{ "BLOB", "Bytes" },
        .{ "UUID", "Uuid" },
    };
    for (table) |row| if (std.ascii.eqlIgnoreCase(row[0], base)) return row[1];
    return "String";
}

/// The class of an error, its SQL state and whether trying again can help.
pub const ErrorClass = struct {
    name: []const u8,
    state: []const u8,
    transient: bool = false,
};

/// Classify a failed statement from the kind and the message DuckDB gave.
pub fn classify(kind: c_uint, msg: []const u8) ErrorClass {
    const has = std.mem.indexOf;
    if (has(u8, msg, "Conflict on update") != null or has(u8, msg, "Conflict on tuple deletion") != null or has(u8, msg, "write-write conflict") != null)
        return .{ .name = "ConflictError", .state = "40001", .transient = true };
    if (has(u8, msg, "deadlock") != null or has(u8, msg, "Deadlock") != null)
        return .{ .name = "DeadlockError", .state = "40P01", .transient = true };
    if (kind == c.DUCKDB_ERROR_CONSTRAINT or has(u8, msg, "Constraint Error") != null)
        return .{ .name = "ConstraintError", .state = "23000" };
    if (kind == c.DUCKDB_ERROR_CATALOG or has(u8, msg, "Catalog Error") != null)
        return .{ .name = "DatabaseError", .state = "42P01" };
    if (kind == c.DUCKDB_ERROR_PARSER or kind == c.DUCKDB_ERROR_SYNTAX or has(u8, msg, "Parser Error") != null)
        return .{ .name = "DatabaseError", .state = "42601" };
    if (kind == c.DUCKDB_ERROR_CONVERSION or has(u8, msg, "Conversion Error") != null)
        return .{ .name = "ConvertError", .state = "22018" };
    return .{ .name = "DatabaseError", .state = "HY000" };
}

test "the Eve type of a DuckDB type" {
    try std.testing.expectEqualStrings("Integer", eveType(c.DUCKDB_TYPE_BIGINT));
    try std.testing.expectEqualStrings("Decimal", eveType(c.DUCKDB_TYPE_DECIMAL));
    try std.testing.expectEqualStrings("Instant", eveType(c.DUCKDB_TYPE_TIMESTAMP_TZ));
    try std.testing.expectEqualStrings("String", eveType(c.DUCKDB_TYPE_INTERVAL));
}

test "the Eve type of a type name" {
    try std.testing.expectEqualStrings("Decimal", eveTypeOfName("DECIMAL(10,2)"));
    try std.testing.expectEqualStrings("Integer", eveTypeOfName("BIGINT"));
    try std.testing.expectEqualStrings("String", eveTypeOfName("VARCHAR"));
}

test "errors are classified by kind and by words" {
    try std.testing.expectEqualStrings("ConflictError", classify(c.DUCKDB_ERROR_TRANSACTION, "TransactionContext Error: Conflict on update!").name);
    try std.testing.expect(classify(0, "Conflict on update").transient);
    try std.testing.expectEqualStrings("23000", classify(c.DUCKDB_ERROR_CONSTRAINT, "Constraint Error: Duplicate key").state);
    try std.testing.expectEqualStrings("42P01", classify(c.DUCKDB_ERROR_CATALOG, "Catalog Error: Table with name x does not exist").state);
    try std.testing.expectEqualStrings("42601", classify(c.DUCKDB_ERROR_PARSER, "Parser Error: syntax error").state);
    try std.testing.expectEqualStrings("HY000", classify(0, "something else").state);
}
