const cp = require("node:child_process");
const origExec = cp.exec;

cp.exec = function (command, options, callback) {
  if (typeof options === "function") {
    callback = options;
    options = undefined;
  }
  if (typeof command === "string" && command.trim().toLowerCase() === "net use") {
    if (callback) callback(null, "", "");
    return { pid: 0, kill() {} };
  }
  return origExec.call(cp, command, options, callback);
};
