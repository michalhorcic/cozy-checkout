import test from 'node:test'
import assert from 'node:assert/strict'
import {readFile} from 'node:fs/promises'

const source = await readFile(new URL('../../../assets/js/adventure/hero_preference.js', import.meta.url), 'utf8')
const {AdventureHero} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)
const preferenceName = 'cozy_adventure_hero'

function browser(t, options = {}) {
  const values = new Map()
  const cookies = new Map()
  const writes = []
  const events = []
  const handlers = new Map()
  const listeners = new Map()
  const removedHandlers = []
  const removedListeners = []
  const availability = {
    storageThrows: false,
    discardStorage: false,
    cookieThrows: false,
    discardCookie: false,
    ...options
  }

  if (options.local !== undefined) values.set(preferenceName, options.local)
  if (options.cookie !== undefined) cookies.set(preferenceName, options.cookie)
  cookies.set('unrelated', 'preserved')

  const localStorage = {
    getItem(key) {
      if (availability.storageThrows) throw new Error('Storage unavailable')
      return values.has(key) ? values.get(key) : null
    },
    setItem(key, value) {
      if (availability.storageThrows) throw new Error('Storage unavailable')
      if (!availability.discardStorage) values.set(key, String(value))
    }
  }
  const window = {
    location: {protocol: options.protocol || 'http:'},
    get localStorage() {
      if (availability.storageThrows) throw new Error('Storage unavailable')
      return localStorage
    }
  }
  const document = {
    get cookie() {
      if (availability.cookieThrows) throw new Error('Cookies unavailable')
      return [...cookies].map(([key, value]) => `${key}=${value}`).join('; ')
    },
    set cookie(value) {
      writes.push(value)
      if (availability.cookieThrows) throw new Error('Cookies unavailable')
      if (availability.discardCookie) return
      const [pair, ...attributes] = value.split(';').map(part => part.trim())
      const separator = pair.indexOf('=')
      const key = pair.slice(0, separator)
      const encodedValue = pair.slice(separator + 1)
      if (attributes.some(attribute => /^max-age=0$/i.test(attribute))) {
        cookies.delete(key)
      } else {
        cookies.set(key, encodedValue)
      }
    }
  }

  for (const [name, value] of Object.entries({window, document})) {
    const descriptor = Object.getOwnPropertyDescriptor(globalThis, name)
    Object.defineProperty(globalThis, name, {configurable: true, writable: true, value})
    t.after(() => {
      if (descriptor) Object.defineProperty(globalThis, name, descriptor)
      else delete globalThis[name]
    })
  }

  const switcher = {open: true}
  const hook = {
    ...AdventureHero,
    el: {
      querySelector(selector) {
        assert.equal(selector, '#adventure-hero-switcher')
        return switcher
      },
      addEventListener(name, callback) {
        assert.equal(typeof callback, 'function')
        assert.equal(listeners.has(name), false, `Duplicate ${name} listener`)
        listeners.set(name, callback)
      },
      removeEventListener(name, callback) {
        removedListeners.push({name, callback})
        assert.equal(listeners.get(name), callback)
        listeners.delete(name)
      }
    },
    handleEvent(name, callback) {
      const reference = Symbol(name)
      handlers.set(reference, {name, callback})
      return reference
    },
    removeHandleEvent(reference) {
      assert.equal(handlers.has(reference), true)
      removedHandlers.push(reference)
      handlers.delete(reference)
    },
    pushEvent(name, payload, callback) {
      assert.equal(typeof callback, 'function')
      events.push({name, payload})
    }
  }

  return {
    hook, switcher, values, cookies, writes, events, handlers, listeners,
    removedHandlers, removedListeners, availability,
    restoreRequests: () => events.filter(event => event.name === 'restore-profile').map(event => event.payload),
    statuses: () => events.filter(event => event.name === 'profile-storage-status').map(event => event.payload),
    serverSelected(id, requestedId = id) {
      const handler = [...handlers.values()].find(handler => handler.name === 'adventure:hero-selected')
      assert.ok(handler, 'Server selection handler must be registered')
      handler.callback({id, requested_id: requestedId})
    },
    change(value, matching = true) {
      const listener = listeners.get('change')
      assert.ok(listener, 'Change listener must be registered')
      listener({target: {
        value,
        matches(selector) {
          assert.equal(selector, '#adventure-profile select')
          return matching
        }
      }})
    }
  }
}

test('localStorage takes precedence over a stale cookie', t => {
  const state = browser(t, {local: 'local-hero', cookie: 'old-hero'})
  state.hook.mounted()
  assert.deepEqual(state.restoreRequests(), [{id: 'local-hero'}])
  assert.equal(state.values.get(preferenceName), 'local-hero')
})

test('cookie-only preference migrates to both stores after server confirmation', t => {
  const id = 'hero with / special characters'
  const state = browser(t, {cookie: encodeURIComponent(id)})
  state.hook.mounted()
  assert.deepEqual(state.restoreRequests(), [{id}])
  state.serverSelected(id)
  assert.equal(state.values.get(preferenceName), id)
  assert.equal(state.cookies.get(preferenceName), encodeURIComponent(id))
  assert.deepEqual(state.statuses(), [{persistent: true}])
})

test('HTTP selection saves a scoped non-Secure cookie and local preference', t => {
  const state = browser(t)
  state.hook.mounted()
  state.serverSelected('lan-hero')
  assert.equal(state.values.get(preferenceName), 'lan-hero')
  assert.equal(state.cookies.get(preferenceName), 'lan-hero')
  assert.equal(state.writes.length, 1)
  assert.match(state.writes[0], /(?:^|;\s*)Path=\/admin\/adventure(?:;|$)/)
  assert.match(state.writes[0], /(?:^|;\s*)SameSite=Lax(?:;|$)/)
  assert.match(state.writes[0], /(?:^|;\s*)Max-Age=31536000(?:;|$)/)
  assert.doesNotMatch(state.writes[0], /(?:^|;\s*)Secure(?:;|$)/i)
  assert.equal(state.cookies.get('unrelated'), 'preserved')
  assert.deepEqual(state.statuses(), [{persistent: true}])
})

test('HTTPS falls back to a Secure cookie when localStorage throws', t => {
  const state = browser(t, {protocol: 'https:', storageThrows: true, cookie: 'previous-hero'})
  assert.doesNotThrow(() => state.hook.mounted())
  assert.deepEqual(state.restoreRequests(), [{id: 'previous-hero'}])
  assert.doesNotThrow(() => state.serverSelected('new-hero'))
  assert.equal(state.cookies.get(preferenceName), 'new-hero')
  assert.match(state.writes.at(-1), /(?:^|;\s*)Secure(?:;|$)/i)
  assert.deepEqual(state.statuses(), [{persistent: true}])
})

test('silently discarded cookies do not prevent local persistence', t => {
  const state = browser(t, {discardCookie: true})
  state.hook.mounted()
  state.serverSelected('local-only')
  assert.equal(state.values.get(preferenceName), 'local-only')
  assert.equal(state.cookies.has(preferenceName), false)
  assert.deepEqual(state.statuses(), [{persistent: true}])
  state.hook.reconnected()
  assert.deepEqual(state.restoreRequests(), [{id: 'local-only'}])
})

test('both unavailable stores report failure without throwing', t => {
  const state = browser(t, {storageThrows: true, cookieThrows: true})
  assert.doesNotThrow(() => state.hook.mounted())
  assert.deepEqual(state.restoreRequests(), [])
  assert.doesNotThrow(() => state.serverSelected('unsaved-hero'))
  assert.deepEqual(state.statuses(), [{persistent: false}])
})

test('readback detects stores that silently discard writes', t => {
  const state = browser(t, {discardStorage: true, discardCookie: true, cookie: 'stale-hero'})
  state.hook.mounted()
  state.serverSelected('different-hero')
  assert.equal(state.values.has(preferenceName), false)
  assert.equal(state.cookies.get(preferenceName), 'stale-hero')
  assert.deepEqual(state.statuses(), [{persistent: false}])
})

test('an empty local tombstone overrides an uncleared stale cookie', t => {
  const state = browser(t, {local: '', cookie: 'stale-hero', discardCookie: true})
  state.hook.mounted()
  assert.deepEqual(state.restoreRequests(), [{id: ''}])
  state.serverSelected('')
  assert.equal(state.values.get(preferenceName), '')
  assert.equal(state.cookies.get(preferenceName), 'stale-hero')
  state.hook.reconnected()
  assert.deepEqual(state.restoreRequests(), [{id: ''}, {id: ''}])
})

test('invalid profile acknowledgement clears the preference and persists a tombstone', t => {
  const state = browser(t, {local: 'deleted-hero', cookie: 'deleted-hero'})
  state.hook.mounted()
  state.serverSelected('')
  assert.equal(state.values.get(preferenceName), '')
  assert.equal(state.cookies.has(preferenceName), false)
  assert.match(state.writes.at(-1), /(?:^|;\s*)Max-Age=0(?:;|$)/)
  assert.equal(state.cookies.get('unrelated'), 'preserved')
  state.hook.reconnected()
  assert.deepEqual(state.restoreRequests(), [{id: 'deleted-hero'}, {id: ''}])
})

test('malformed cookie encoding is ignored without breaking mounting', t => {
  const state = browser(t, {cookie: '%E0%A4%A'})
  assert.doesNotThrow(() => state.hook.mounted())
  assert.deepEqual(state.restoreRequests(), [])
  assert.equal(state.values.has(preferenceName), false)
  assert.equal(state.writes.length, 0)
  state.serverSelected('valid-hero')
  assert.equal(state.values.get(preferenceName), 'valid-hero')
})

test('a malformed cookie cannot clear a good local preference', t => {
  const state = browser(t, {local: 'valid-hero', cookie: '%E0%A4%A'})
  assert.doesNotThrow(() => state.hook.mounted())
  assert.deepEqual(state.restoreRequests(), [{id: 'valid-hero'}])
  assert.equal(state.values.get(preferenceName), 'valid-hero')
  assert.equal(state.writes.length, 0)
})

test('blocked cookie access cannot prevent restoration from localStorage', t => {
  const state = browser(t, {local: 'local-hero', cookieThrows: true})
  assert.doesNotThrow(() => state.hook.mounted())
  assert.deepEqual(state.restoreRequests(), [{id: 'local-hero'}])
  assert.doesNotThrow(() => state.serverSelected('next-hero'))
  assert.equal(state.values.get(preferenceName), 'next-hero')
  assert.deepEqual(state.statuses(), [{persistent: true}])
})

test('reconnection restores the current stored preference without duplicating listeners', t => {
  const state = browser(t, {local: 'first-hero'})
  state.hook.mounted()
  state.values.set(preferenceName, 'second-hero')
  state.hook.reconnected()
  assert.deepEqual(state.restoreRequests(), [{id: 'first-hero'}, {id: 'second-hero'}])
  assert.equal(state.handlers.size, 1)
  assert.equal(state.listeners.size, 1)
})

test('profile changes persist immediately before any server acknowledgement', t => {
  const state = browser(t)
  state.hook.mounted()
  state.change('ignored-hero', false)
  assert.equal(state.values.has(preferenceName), false)
  assert.equal(state.writes.length, 0)
  state.change('selected-hero')
  assert.equal(state.values.get(preferenceName), 'selected-hero')
  assert.equal(state.cookies.get(preferenceName), 'selected-hero')
  assert.deepEqual(state.statuses(), [{persistent: true}])
  state.hook.reconnected()
  assert.deepEqual(state.restoreRequests(), [{id: 'selected-hero'}])
  state.serverSelected('confirmed-hero', 'selected-hero')
  assert.equal(state.values.get(preferenceName), 'confirmed-hero')
  assert.equal(state.cookies.get(preferenceName), 'confirmed-hero')
})

test('storage status is emitted only when persistence availability changes', t => {
  const state = browser(t)
  state.hook.mounted()
  state.serverSelected('first-hero')
  state.serverSelected('second-hero')
  assert.deepEqual(state.statuses(), [{persistent: true}])
  state.availability.storageThrows = true
  state.availability.cookieThrows = true
  state.serverSelected('third-hero')
  state.serverSelected('fourth-hero')
  assert.deepEqual(state.statuses(), [{persistent: true}, {persistent: false}])
  state.availability.storageThrows = false
  state.serverSelected('fifth-hero')
  assert.deepEqual(state.statuses(), [{persistent: true}, {persistent: false}, {persistent: true}])
})

test('a late restore acknowledgement cannot overwrite a newer manual selection', t => {
  const state = browser(t, {local: 'previous-hero'})
  state.hook.mounted()
  state.change('new-hero')
  state.serverSelected('previous-hero')
  assert.equal(state.values.get(preferenceName), 'new-hero')
  assert.equal(state.cookies.get(preferenceName), 'new-hero')
  state.serverSelected('new-hero')
  assert.equal(state.hook.pendingHero, undefined)
})

test('rejection of the latest manual choice still clears both stores', t => {
  const state = browser(t)
  state.hook.mounted()
  state.change('deactivated-hero')
  state.serverSelected('', 'deactivated-hero')
  assert.equal(state.values.get(preferenceName), '')
  assert.equal(state.cookies.has(preferenceName), false)
  assert.equal(state.hook.pendingHero, undefined)
})

test('destroying the hook unregisters the server handler and the change listener', t => {
  const state = browser(t)
  state.hook.mounted()
  const [reference] = state.handlers.keys()
  const listener = state.listeners.get('change')
  state.hook.destroyed()
  assert.equal(state.handlers.size, 0)
  assert.equal(state.listeners.size, 0)
  assert.deepEqual(state.removedHandlers, [reference])
  assert.deepEqual(state.removedListeners, [{name: 'change', callback: listener}])
})


test('hero chooser follows accepted selection and reopens after clearing', t => {
  const state = browser(t)
  state.hook.mounted()
  state.serverSelected('hero')
  assert.equal(state.switcher.open, false)
  state.change('')
  state.serverSelected('')
  assert.equal(state.switcher.open, true)
  state.change('new-hero')
  state.serverSelected('hero')
  assert.equal(state.switcher.open, true, 'late acknowledgement cannot close a pending choice')
  state.serverSelected('new-hero')
  assert.equal(state.switcher.open, false)
})
