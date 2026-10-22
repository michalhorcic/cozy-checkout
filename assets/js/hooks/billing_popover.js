// Native popovers stay above table clipping and provide Escape and outside-click dismissal.
export const BillingPopover = {
  mounted() {
    this.trigger = this.el.querySelector("[popovertarget]")
    this.panel = this.el.querySelector("[popover]")
    this.open = () => this.panel.matches(":popover-open")
    this.position = () => {
      if (!this.open()) return
      const anchor = this.trigger.getBoundingClientRect()
      const panel = this.panel.getBoundingClientRect()
      const margin = 12
      const below = anchor.bottom + 8
      const top = below + panel.height <= window.innerHeight - margin
        ? below
        : Math.max(margin, anchor.top - panel.height - 8)
      const left = Math.max(margin, Math.min(anchor.right - panel.width, window.innerWidth - panel.width - margin))
      this.panel.style.top = `${top}px`
      this.panel.style.left = `${left}px`
    }
    this.show = () => {
      clearTimeout(this.closeTimer)
      this.panel.showPopover()
      this.position()
    }
    this.hide = () => {
      clearTimeout(this.closeTimer)
      this.panel.hidePopover()
    }
    this.enter = event => {
      if (event.pointerType === "mouse") {
        this.suppressFocus = false
        this.show()
      }
    }
    this.leave = () => {
      this.closeTimer = setTimeout(() => {
        if (!this.el.contains(document.activeElement) || !document.activeElement.matches(":focus-visible")) this.hide()
      }, 150)
    }
    this.focus = event => { if (!this.suppressFocus && event.target.matches(":focus-visible")) this.show() }
    this.blur = event => {
      if (!this.el.contains(event.relatedTarget)) {
        this.suppressFocus = false
        this.hide()
      }
    }
    this.keydown = event => {
      if (event.key === "Escape") {
        this.suppressFocus = true
        this.hide()
      }
    }
    this.toggle = () => {
      this.trigger.setAttribute("aria-expanded", String(this.open()))
      this.position()
    }
    this.el.addEventListener("pointerenter", this.enter)
    this.el.addEventListener("pointerleave", this.leave)
    this.el.addEventListener("focusin", this.focus)
    this.el.addEventListener("focusout", this.blur)
    this.el.addEventListener("keydown", this.keydown)
    this.panel.addEventListener("toggle", this.toggle)
    window.addEventListener("resize", this.position)
    window.addEventListener("scroll", this.position, true)
  },
  updated() { this.toggle() },
  destroyed() {
    clearTimeout(this.closeTimer)
    this.el.removeEventListener("pointerenter", this.enter)
    this.el.removeEventListener("pointerleave", this.leave)
    this.el.removeEventListener("focusin", this.focus)
    this.el.removeEventListener("focusout", this.blur)
    this.el.removeEventListener("keydown", this.keydown)
    this.panel.removeEventListener("toggle", this.toggle)
    window.removeEventListener("resize", this.position)
    window.removeEventListener("scroll", this.position, true)
  }
}
