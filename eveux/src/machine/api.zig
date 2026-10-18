//! @eve-module api: the names of the machine messages that eveux sends, and the shape of their answers
//! @spec spec/library/machine.md#the-machine-api
//! @feature F-NET-08
//! @decision D-165, D-193
//! The transport is `shared.link.Link` (evetx): a child `eve --stdio`, one JSON message a line, `vm.output` notifications.
//! This file only holds names, so a message is searched in one place; the methods marked (new) are the proposals of
//! eveux/design/notes/elaboration.md section 6 and do not exist in the machine yet.
pub const vm = struct {
    pub const ping = "vm.ping";
    pub const stat = "vm.stat";
    pub const open = "vm.open"; // a session: one for each console tab
    pub const eval = "vm.eval"; // one line of the prompt, `"stream": true` for output as it comes
    pub const close = "vm.close";
    pub const run = "vm.run";
    pub const cancel = "vm.cancel";
    pub const shell = "vm.shell";
};

pub const db = struct {
    pub const query = "db.query";
    pub const execute = "db.execute";
    pub const stat = "db.stat";
    pub const tree = "db.tree"; // (new) children of a node of the object tree
    pub const describe = "db.describe"; // (new) columns, keys, indexes of a table
    pub const sample = "db.sample"; // (new) the first rows of a table, for the data tab
};

pub const files = struct {
    pub const list = "fs.list"; // (new)
    pub const read = "fs.read"; // (new)
    pub const write = "fs.write"; // (new)
    pub const delete = "fs.delete"; // (new)
};

pub const deploy = struct {
    pub const plan = "deploy.plan"; // (new) the manifest of the target and the checks
    pub const apply = "deploy.apply"; // (new)
    pub const versions = "deploy.versions"; // (new)
    pub const activate = "deploy.activate"; // (new)
};

pub const jobs = struct {
    pub const list = "job.list"; // (new)
    pub const start = "job.start"; // (new)
    pub const runs = "job.runs"; // (new)
    pub const log_tail = "log.tail"; // (new) subscribe to the lines of a log
};

pub const debug = struct {
    pub const start = "dbg.start"; // (new) F-TLS-04
    pub const step = "dbg.step";
    pub const breakpoint = "dbg.break";
    pub const locals = "dbg.locals";
    pub const stack = "dbg.stack";
};
