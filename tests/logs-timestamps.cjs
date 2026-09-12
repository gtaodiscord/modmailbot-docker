// Run inside the image with node -e, or pass an upstream checkout as argv[2].
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { createRequire } = require("node:module");
const vm = require("node:vm");

const root = path.resolve(process.argv[2] || process.cwd());
const upstreamRequire = createRequire(path.join(root, "package.json"));
const source = fs.readFileSync(path.join(root, "src/modules/logs.js"), "utf8");
const messages = [];
const handlers = [];
const fixtures = [
  { thread_number: 1, created_at: "2025-08-04 14:30:00" },
  { thread_number: 2, created_at: "2024-12-31 23:59:00" },
];
const dependencies = {
  "moment": upstreamRequire("moment"),
  "../data/threads": { getClosedThreadsByUserId: async () => [...fixtures] },
  "../utils": {
    getOrFetchChannel: async () => ({ createMessage: async text => messages.push(text) }),
    chunk: lines => [lines],
  },
  "../data/logs": { getLogUrl: async thread => `https://example.com/log/${thread.thread_number}` },
  "../data/constants": { THREAD_STATUS: {} },
};
const moduleStub = { exports: {} };
vm.runInNewContext(source, {
  module: moduleStub,
  require: name => {
    assert.ok(Object.hasOwn(dependencies, name), `Unexpected dependency: ${name}`);
    return dependencies[name];
  },
});
moduleStub.exports({
  bot: {},
  config: { prefix: "!" },
  commands: {
    addInboxServerCommand: (name, syntax, handler) => {
      if (name === "logs") handlers.push(handler);
    },
    addInboxThreadCommand: () => {},
  },
  hooks: { afterThreadClose: () => {} },
});

(async () => {
  assert.equal(handlers.length, 2);
  for (const [index, handler] of handlers.entries()) {
    messages.length = 0;
    await handler({ channel: { id: "channel" } }, index ? {} : { userId: "user" }, { user_id: "user" });
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(messages.join("\n"), [
      "**Log files for <@user>:**",
      "`#1` <t:1754317800:f>: <https://example.com/log/1>",
      "`#2` <t:1735689540:f>: <https://example.com/log/2>",
    ].join("\n"));
  }
  console.log("PASS: both !logs forms emit renderable local timestamps in Unix seconds");
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
