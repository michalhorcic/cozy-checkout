const cookieName = 'cozy_adventure_hero'
const cookiePath = '/admin/adventure'
const oneYear = 365 * 24 * 60 * 60

// A browser preference, never an authentication or authorization token.
export const AdventureHero = {
  mounted() {
    this.preferenceHandler = this.handleEvent('adventure:hero-selected', ({id}) => {
      this.saveHero(id)
    })
    this.restoreHero()
  },
  reconnected() {
    this.restoreHero()
  },
  restoreHero() {
    try {
      const cookie = document.cookie.split(';').map(value => value.trim())
        .find(value => value.startsWith(`${cookieName}=`))
      if (cookie) {
        const id = decodeURIComponent(cookie.slice(cookieName.length + 1))
        this.pushEvent('restore-profile', {id}, () => {})
      }
    } catch (_error) {
      // Blocked cookies or a malformed preference must not break the game.
      this.saveHero('')
    }
  },
  saveHero(id) {
    try {
      const secure = window.location.protocol === 'https:' ? '; Secure' : ''
      const age = id ? oneYear : 0
      document.cookie = `${cookieName}=${encodeURIComponent(id || '')}; Path=${cookiePath}; Max-Age=${age}; SameSite=Lax${secure}`
    } catch (_error) {
      // Selection still works for this page when cookies are unavailable.
    }
  },
  destroyed() {
    this.removeHandleEvent(this.preferenceHandler)
  }
}
