// Feed the native LiveView uploader in groups of two. Queued files stay in the
// browser; the server persists each finished source independently.
export const IncomingBatchUpload = {
  mounted() {
    this.queue = []
    this.feeding = false
    this.registered = false
    this.synthetic = false
    this.handleEvent("batch-upload-remove", ({index}) => {
      this.queue.splice(Number(index), 1)
      this.report()
    })
    this.onChange = event => {
      if (event.target.type !== "file" || this.synthetic) return
      event.stopImmediatePropagation()
      event.preventDefault()
      this.queue.push(...Array.from(event.target.files))
      event.target.value = ""
      this.report()
      this.feed()
    }
    this.el.addEventListener("change", this.onChange, true)
  },
  updated() {
    const active = Number(this.el.dataset.active)
    if (active > 0) this.registered = true
    if (this.feeding && this.registered && active === 0) {
      this.feeding = false
      this.registered = false
    }
    this.feed()
  },
  report() {
    this.pushEvent("upload-queue", {names: this.queue.map(file => file.name)})
  },
  feed() {
    if (this.feeding || this.queue.length === 0 || Number(this.el.dataset.active) > 0) return
    this.feeding = true
    const transfer = new DataTransfer()
    this.queue.splice(0, 2).forEach(file => transfer.items.add(file))
    const input = this.el.querySelector('input[type="file"]')
    input.files = transfer.files
    this.synthetic = true
    input.dispatchEvent(new Event("change", {bubbles: true}))
    this.synthetic = false
    this.report()
  },
  destroyed() {
    this.el.removeEventListener("change", this.onChange, true)
  }
}
