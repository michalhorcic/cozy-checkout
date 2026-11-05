export const IncomingDocumentPreview = {
  mounted() {
    this.el.querySelector("[data-zoom]").addEventListener("input", event => {
      this.el.querySelector("[data-original]").style.width = `${event.target.value}%`
    })
  }
}
