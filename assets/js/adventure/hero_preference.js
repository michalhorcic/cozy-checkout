const cookieName = 'cozy_adventure_hero'
const cookiePath = '/admin/adventure'
const oneYear = 365 * 24 * 60 * 60

// A browser preference, never an authentication or authorization token.
export const AdventureHero = {
  mounted() {
    this.preferenceHandler = this.handleEvent('adventure:hero-selected', ({id, requested_id: requestedId}) => {
      // A late restore reply must not overwrite a more recent manual choice.
      if (this.pendingHero !== undefined && requestedId !== this.pendingHero) return
      this.pendingHero = undefined
      this.saveHero(id)
      // Close only after the server accepts a hero; clearing/invalidating reopens the choice.
      const switcher = this.el.querySelector?.('#adventure-hero-switcher')
      if (switcher) switcher.open = !id
    })
    this.selectionHandler = event => {
      if (event.target.matches('#adventure-profile select')) {
        this.pendingHero = event.target.value
        this.saveHero(this.pendingHero)
      }
    }
    this.el.addEventListener('change', this.selectionHandler)
    this.restoreHero()
  },
  reconnected() {
    this.restoreHero()
  },
  restoreHero() {
    let id = null
    try {
      id = window.localStorage.getItem(cookieName)
    } catch (_error) {
      // Cookies remain a fallback when browser storage is blocked.
    }
    if (id === null) id = this.readCookie()
    if (id !== null) this.pushEvent('restore-profile', {id}, () => {})
  },
  readCookie() {
    try {
      const cookie = document.cookie.split(';').map(value => value.trim())
        .find(value => value.startsWith(`${cookieName}=`))
      return cookie ? decodeURIComponent(cookie.slice(cookieName.length + 1)) : null
    } catch (_error) {
      return null
    }
  },
  saveHero(id) {
    const value = id || ''
    let storedLocally = false
    let storedInCookie = false
    try {
      // An empty value prevents an old cookie from restoring a forgotten hero.
      window.localStorage.setItem(cookieName, value)
      storedLocally = window.localStorage.getItem(cookieName) === value
    } catch (_error) {
      // Try cookies independently of localStorage failures.
    }
    try {
      const secure = window.location.protocol === 'https:' ? '; Secure' : ''
      const age = id ? oneYear : 0
      document.cookie = `${cookieName}=${encodeURIComponent(value)}; Path=${cookiePath}; Max-Age=${age}; SameSite=Lax${secure}`
      storedInCookie = this.readCookie() === (value || null)
    } catch (_error) {
      // Selection still works for this page when cookies are unavailable.
    }
    const persistent = storedLocally || storedInCookie
    if (persistent !== this.storageAvailable) {
      this.storageAvailable = persistent
      this.pushEvent('profile-storage-status', {persistent}, () => {})
    }
  },
  destroyed() {
    this.el.removeEventListener('change', this.selectionHandler)
    this.removeHandleEvent(this.preferenceHandler)
  }
}
