//! @eve-module ewp_protocol
//! @spec comp/evedb/README.md#5-the-native-protocol-ewp-db
//! @decision D-199
//! @tests comp/evedb/protocol/ewp.zig, comp/evedb/protocol/batch.zig
//! The wire protocol between the DuckDB server and the native driver `evedb://`: the frames, the column batches and a client.
//!
//! These three files are shared, not copied (D-199 5). The server (`comp/evedb/build.zig`) and the Eve side (the root
//! `build.zig`, for the driver in `evevm`) each make the module `ewp_protocol` from this file, so there is one protocol and
//! one place to change it. The check from the other side is `script/evedb_check.py`, written from the document alone.

/// The frames of EWP-db: handshake, statements, errors, transactions, status.
pub const ewp = @import("ewp.zig");
/// Column batches: result sets and loads column by column.
pub const batch = @import("batch.zig");
/// A client of the frames, for `evedb sql --connect`, `evedb status`, `evedb stop` and the driver.
pub const client = @import("client.zig");

// @eve-impl run the tests of the three files when this module is a test root
test {
    _ = ewp;
    _ = batch;
    _ = client;
}
