// Native modal dialog supplies focus trapping, Escape and background inertness.
export const AdventureHelp = {
  mounted() {
    this.onOpen = () => {
      if (this.el.open) return
      this.opener = document.activeElement
      this.el.showModal()
      document.getElementById('adventure-help-open')?.setAttribute('aria-expanded', 'true')
    }
    this.onCloseRequest = () => this.el.close()
    this.onBackdrop = event => {
      if (event.target === this.el) this.el.close()
    }
    this.onClosed = () => {
      document.getElementById('adventure-help-open')?.setAttribute('aria-expanded', 'false')
      if (this.opener?.isConnected) this.opener.focus()
    }
    this.onKeyDown = event => {
      if (event.key !== 'Tab') return
      const controls = Array.from(this.el.querySelectorAll(
        'button:not([disabled]), a[href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex="0"]'
      )).filter(control => control.getClientRects().length > 0)
      const first = controls[0]
      const last = controls[controls.length - 1]
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault()
        last?.focus()
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault()
        first?.focus()
      }
    }
    this.el.addEventListener('adventure:open-help', this.onOpen)
    this.el.addEventListener('adventure:close-help', this.onCloseRequest)
    this.el.addEventListener('click', this.onBackdrop)
    this.el.addEventListener('close', this.onClosed)
    this.el.addEventListener('keydown', this.onKeyDown)
  },
  destroyed() {
    if (this.el.open) this.el.close()
    this.el.removeEventListener('adventure:open-help', this.onOpen)
    this.el.removeEventListener('adventure:close-help', this.onCloseRequest)
    this.el.removeEventListener('click', this.onBackdrop)
    this.el.removeEventListener('close', this.onClosed)
    this.el.removeEventListener('keydown', this.onKeyDown)
  }
}
