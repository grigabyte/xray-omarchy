// Runs one of the panel's JavaScript libraries under Node, as written: the
// file is read, its QML-only first line (".pragma library") is blanked out,
// and the rest is evaluated in a fresh vm context whose globals are returned,
// so a test calls the very functions the shell loads.
const { readFileSync } = require("node:fs")
const { resolve } = require("node:path")
const { createContext, runInContext } = require("node:vm")

exports.ROOT = resolve(__dirname, "..")

exports.load = function (file) {
  const text = readFileSync(resolve(exports.ROOT, file), "utf8")
  const sandbox = createContext({})
  runInContext(text.replace(/^\s*\.pragma\s+library\s*$/m, ""), sandbox, { filename: file })
  return sandbox
}
