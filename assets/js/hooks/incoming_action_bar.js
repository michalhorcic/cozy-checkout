export const IncomingActionBar = {
  mounted() {
    this.update = () => {
      const viewport = window.visualViewport
      const keyboard = viewport && window.matchMedia("(max-width: 1023px)").matches
        ? Math.max(0, window.innerHeight - viewport.height - viewport.offsetTop) : 0
      this.el.style.bottom = `${keyboard}px`
      this.el.parentElement.style.setProperty("--incoming-actions-height", `${this.el.offsetHeight}px`)
    }
    this.beforeUnload = event => {
      if (this.el.dataset.unsaved !== "true") return
      event.preventDefault()
      event.returnValue = ""
    }
    window.addEventListener("beforeunload", this.beforeUnload)
    this.observer = new ResizeObserver(this.update)
    this.observer.observe(this.el)
    window.addEventListener("resize", this.update)
    window.visualViewport?.addEventListener("resize", this.update)
    window.visualViewport?.addEventListener("scroll", this.update)
    this.update()
  },
  updated() { this.update() },
  destroyed() {
    this.observer.disconnect()
    window.removeEventListener("beforeunload", this.beforeUnload)
    window.removeEventListener("resize", this.update)
    window.visualViewport?.removeEventListener("resize", this.update)
    window.visualViewport?.removeEventListener("scroll", this.update)
  }
}
