export const MenuEditor = {
  mounted() {
    this.saving = false
    this.libraryOpen = this.el.dataset.libraryOpen === "true"
    this.dirty = () => this.el.dataset.dirty === "true" && !this.saving
    this.beforeUnload = event => {
      if (this.dirty()) {
        event.preventDefault()
        event.returnValue = ""
      }
    }
    this.navigate = event => {
      const link = event.target.closest("a[href]")
      if (link && this.dirty() && !window.confirm("Zahodit neuložené změny menu?")) {
        event.preventDefault()
        event.stopImmediatePropagation()
      }
    }
    this.dragStart = event => {
      const card = event.target.closest("[data-recipe-id]")
      if (card) {
        event.dataTransfer.setData("application/x-menu-recipe", card.dataset.recipeId)
        event.dataTransfer.effectAllowed = "copy"
      }
    }
    this.dragOver = event => {
      const target = event.target.closest("[data-slot-index][data-role]")
      if (target && [...event.dataTransfer.types].includes("application/x-menu-recipe")) {
        event.preventDefault()
        event.dataTransfer.dropEffect = "copy"
      }
    }
    this.drop = event => {
      const target = event.target.closest("[data-slot-index][data-role]")
      const id = event.dataTransfer.getData("application/x-menu-recipe")
      if (target && id) {
        event.preventDefault()
        this.pushEventTo(this.el, "drop_recipe", {id, index: target.dataset.slotIndex, role: target.dataset.role})
      }
    }
    this.keydown = event => {
      if (this.el.dataset.libraryOpen !== "true" || !window.matchMedia("(max-width: 1023px)").matches) return
      if (event.key === "Escape") {
        event.stopImmediatePropagation()
        this.pushEventTo(this.el, "close_library", {})
      }
      if (event.key === "Tab") {
        const controls = [...this.el.querySelectorAll("[data-menu-library] input, [data-menu-library] button:not([disabled])")]
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
    }
    this.el.addEventListener("keydown", this.keydown, true)
    this.handleEvent("menu-editor-saved", () => { this.saving = true })
    this.historyState = history.state
    this.currentURL = location.href
    this.popState = event => {
      if (this.dirty() && !window.confirm("Zahodit neuložené změny menu?")) {
        event.stopImmediatePropagation()
        history.pushState(this.historyState, "", this.currentURL)
      }
    }
    window.addEventListener("popstate", this.popState, true)
    window.addEventListener("beforeunload", this.beforeUnload)
    document.addEventListener("click", this.navigate, true)
    this.el.addEventListener("dragstart", this.dragStart)
    this.el.addEventListener("dragover", this.dragOver)
    this.el.addEventListener("drop", this.drop)
  },
  updated() {
    const open = this.el.dataset.libraryOpen === "true"
    if (open !== this.libraryOpen && window.matchMedia("(max-width: 1023px)").matches) {
      if (open) {
        this.previousFocus = document.activeElement
        this.el.querySelector("[data-menu-library] input[type=search]")?.focus()
      } else if (this.previousFocus?.isConnected) {
        this.previousFocus.focus()
      }
    }
    this.libraryOpen = open
  },
  destroyed() {
    this.el.removeEventListener("keydown", this.keydown, true)
    window.removeEventListener("popstate", this.popState, true)
    window.removeEventListener("beforeunload", this.beforeUnload)
    document.removeEventListener("click", this.navigate, true)
    this.el.removeEventListener("dragstart", this.dragStart)
    this.el.removeEventListener("dragover", this.dragOver)
    this.el.removeEventListener("drop", this.drop)
  }
}

export const MenuPreview = {
  mounted() {
    this.pinned = false
    this.enter = () => { this.el.open = true }
    this.leave = () => { if (!this.pinned && !this.el.contains(document.activeElement)) this.el.open = false }
    this.focusOut = () => queueMicrotask(this.leave)
    this.click = event => {
      if (event.target.closest("summary")) {
        event.preventDefault()
        this.pinned = !this.pinned
        this.el.open = this.pinned
      }
    }
    this.el.addEventListener("pointerenter", this.enter)
    this.el.addEventListener("pointerleave", this.leave)
    this.el.addEventListener("focusin", this.enter)
    this.el.addEventListener("focusout", this.focusOut)
    this.el.addEventListener("click", this.click)
  },
  destroyed() {
    this.el.removeEventListener("pointerenter", this.enter)
    this.el.removeEventListener("pointerleave", this.leave)
    this.el.removeEventListener("focusin", this.enter)
    this.el.removeEventListener("focusout", this.focusOut)
    this.el.removeEventListener("click", this.click)
  }
}
