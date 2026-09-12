// Temporary image fix until an upstream release includes localized !logs dates.
const fs = require("node:fs");
const path = require("node:path");

const file = path.join(process.argv[2] || "/app", "src/modules/logs.js");
const before = [
  '      const formattedDate = moment.utc(userThread.created_at).format("MMM Do [at] HH:mm [UTC]");',
  '      return `\\`#${userThread.thread_number}\\` \\`${formattedDate}\\`: ${formattedLogUrl}`;',
].join("\n");
const after = [
  '      const timestamp = moment.utc(userThread.created_at).unix();',
  '      return `\\`#${userThread.thread_number}\\` <t:${timestamp}:f>: ${formattedLogUrl}`;',
].join("\n");

// A later upstream fix or refactor must not block automatic release builds.
if (fs.existsSync(file) && fs.readFileSync(file, "utf8").includes(before)) {
  fs.writeFileSync(file, fs.readFileSync(file, "utf8").replace(before, after));
  console.log("Applied localized !logs timestamps");
} else {
  console.log("Skipped !logs timestamp fix: upstream no longer contains the legacy format");
}
