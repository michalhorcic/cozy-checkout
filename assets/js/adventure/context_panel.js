// On a phone the contextual panel is a full-screen dialog; desktop keeps it inline.
export const AdventureContext = {
  mounted() {
    this.media = window.matchMedia("(max-width: 900px)")
    this.onMedia = () => this.syncPanel()
    this.media.addEventListener("change", this.onMedia)
    this.onPointer = event => {
      if (this.el.contains(event.target) && event.target.closest("[phx-click='open-duty-quest'], [phx-click='duty-history'], [phx-click='prepare-duty'], [phx-click='prepare-completion']")) {
        this.dialogOpener = event.target.closest("button")
      }
      if (!this.el.contains(event.target) && event.target.closest("[phx-click='operation-area'], [phx-click='world-panel']")) {
        this.opener = event.target.closest("button")
      }
    }
    this.onKey = event => {
      if (!this.modal) return
      if (event.key === "Escape") {
        event.preventDefault()
        event.stopPropagation()
        this.pushEvent("world-panel", {panel: "continue"})
      }
      if (event.key !== "Tab") return
      const controls = Array.from(this.el.querySelectorAll("a[href], button:not([disabled]), input, select, textarea, summary, [tabindex='0']"))
        .filter(el => el.getClientRects().length > 0)
      const first = controls[0], last = controls.at(-1)
      if (event.shiftKey && (document.activeElement === first || document.activeElement === this.el)) {
        event.preventDefault(); last?.focus()
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault(); first?.focus()
      }
    }
    document.addEventListener("click", this.onPointer, true)
    this.el.addEventListener("keydown", this.onKey)
    this.syncPanel()
  },
  updated() { this.syncPanel() },
  syncPanel() {
    const overlay = this.el.dataset.dialogOpen === "true"
    const modal = this.media.matches && this.el.dataset.panel !== "continue" && this.el.dataset.view === "world" && !overlay
    if (modal === this.modal) return
    this.modal = modal
    if (modal) {
      this.previousOverflow = document.body.style.overflow
      document.body.style.overflow = "hidden"
      this.el.setAttribute("role", "dialog")
      this.el.setAttribute("aria-modal", "true")
      // Make the rest of the game inert while leaving this panel interactive.
      this.inertElements = []
      let child = this.el
      while (child.parentElement && child.parentElement !== document.body) {
        for (const sibling of child.parentElement.children) {
          if (sibling !== child && !sibling.inert) { sibling.inert = true; this.inertElements.push(sibling) }
        }
        child = child.parentElement
      }
      const target = this.dialogOpener?.isConnected ? this.dialogOpener : this.el
      target.focus()
      this.dialogOpener = null
    } else {
      this.releasePanel()
      if (!overlay && this.opener?.isConnected) this.opener.focus()
    }
  },
  releasePanel() {
    for (const element of this.inertElements || []) element.inert = false
    this.inertElements = []
    this.el.removeAttribute("role")
    this.el.removeAttribute("aria-modal")
    if (this.previousOverflow !== undefined) {
      document.body.style.overflow = this.previousOverflow
      this.previousOverflow = undefined
    }
  },
  destroyed() {
    this.releasePanel()
    this.media.removeEventListener("change", this.onMedia)
    document.removeEventListener("click", this.onPointer, true)
    this.el.removeEventListener("keydown", this.onKey)
  }
}
