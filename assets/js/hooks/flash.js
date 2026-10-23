export const Flash = {
  mounted() {
    this.message = this.el.textContent
    this.scheduleDismiss()
  },

  updated() {
    // Unrelated LiveView patches must not keep an existing notice alive.
    if (this.message !== this.el.textContent) {
      this.message = this.el.textContent
      this.scheduleDismiss()
    }
  },

  scheduleDismiss() {
    clearTimeout(this.dismissTimer)
    this.dismissTimer = setTimeout(() => {
      // Reuse the close button's LiveView command to clear server flash too.
      this.el.querySelector("button[phx-click]").click()
    }, 5000)
  },

  destroyed() {
    clearTimeout(this.dismissTimer)
  }
}
