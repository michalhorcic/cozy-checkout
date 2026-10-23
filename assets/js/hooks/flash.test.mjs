import {readFile} from "node:fs/promises"
import assert from "node:assert/strict"
import {test} from "node:test"

const source = await readFile(new URL("./flash.js", import.meta.url), "utf8")
const {Flash} = await import(`data:text/javascript,${encodeURIComponent(source)}`)

test("dismisses after five seconds, resets for new content and cancels on removal", (t) => {
  t.mock.timers.enable({apis: ["setTimeout"]})
  let closed = 0
  const hook = {
    ...Flash,
    el: {
      textContent: "Saved",
      querySelector: () => ({click: () => closed++})
    }
  }

  hook.mounted()
  t.mock.timers.tick(4000)
  hook.updated()
  t.mock.timers.tick(999)
  assert.equal(closed, 0)
  t.mock.timers.tick(1)
  assert.equal(closed, 1)

  hook.el.textContent = "Item added"
  hook.updated()
  t.mock.timers.tick(4000)
  hook.el.textContent = "Item removed"
  hook.updated()
  t.mock.timers.tick(1000)
  assert.equal(closed, 1)
  t.mock.timers.tick(4000)
  assert.equal(closed, 2)

  hook.el.textContent = "Saved again"
  hook.updated()
  hook.destroyed()
  t.mock.timers.tick(5000)
  assert.equal(closed, 2)
})
