// Keep browser navigation from discarding a calculation that has not been saved.
export const CalculationEditor = {
  mounted() {
    this.dirty = this.el.dataset.dirty === "true"
    this.onInput = () => { this.dirty = true }
    this.onUnload = event => {
      if (!this.dirty) return
      event.preventDefault()
      event.returnValue = ""
    }
    this.onNavigate = event => {
      const link = event.target.closest("a[href]")
      if (!this.dirty || !link || link.target === "_blank" || link.hasAttribute("download") ||
          event.ctrlKey || event.metaKey || event.shiftKey || event.altKey || event.button !== 0) return
      if (!window.confirm("Máte neuložené změny kalkulace. Opravdu chcete odejít?")) {
        event.preventDefault()
        event.stopImmediatePropagation()
      }
    }
    this.onInvalid = event => { event.target.closest("details")?.setAttribute("open", "") }
    this.el.addEventListener("input", this.onInput)
    this.el.addEventListener("invalid", this.onInvalid, true)
    window.addEventListener("beforeunload", this.onUnload)
    document.addEventListener("click", this.onNavigate, true)
  },
  updated() {
    this.dirty = this.el.dataset.dirty === "true"
  },
  destroyed() {
    this.el.removeEventListener("input", this.onInput)
    this.el.removeEventListener("invalid", this.onInvalid, true)
    window.removeEventListener("beforeunload", this.onUnload)
    document.removeEventListener("click", this.onNavigate, true)
  }
}
