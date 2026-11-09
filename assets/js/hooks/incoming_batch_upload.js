import {prepareIncomingPhoto} from "../incoming_photo"

// Only two files enter LiveView at once. Decode one photo at a time to keep
// memory bounded on phones; raw files stay in the browser until conversion.
export const IncomingBatchUpload = {
  mounted() {
    this.queue = []
    this.feeding = false
    this.preparing = false
    this.registered = false
    this.synthetic = false
    this.disposed = false
    this.handleEvent("batch-upload-remove", ({index}) => {
      this.queue.splice(Number(index), 1)
      this.report()
    })
    // LiveView also listens for input events on file fields. Stop the native
    // input event before it can register the unprocessed files for upload.
    this.onInput = event => {
      if (event.target.type !== "file" || this.synthetic) return
      event.stopImmediatePropagation()
      event.preventDefault()
    }
    this.onChange = event => {
      if (event.target.type !== "file" || this.synthetic) return
      event.stopImmediatePropagation()
      event.preventDefault()
      this.queue.push(...Array.from(event.target.files))
      event.target.value = ""
      this.report()
      this.feed()
    }
    this.el.addEventListener("input", this.onInput, true)
    this.el.addEventListener("change", this.onChange, true)
  },
  updated() {
    const active = Number(this.el.dataset.active)
    if (active > 0) {
      this.registered = true
      if (this.preparing) {
        this.preparing = false
        this.report()
      }
    }
    if (this.feeding && this.registered && active === 0) {
      this.feeding = false
      this.registered = false
    }
    this.feed()
  },
  report() {
    if (!this.disposed) this.pushEvent("upload-queue", {
      names: this.queue.map(file => file.name), preparing: this.preparing
    })
  },
  async feed() {
    if (this.disposed || this.feeding || this.queue.length === 0 || Number(this.el.dataset.active) > 0) return
    this.feeding = true
    this.preparing = true
    this.report()
    const transfer = new DataTransfer()
    for (const file of this.queue.slice(0, 2)) {
      if (!this.queue.includes(file)) continue
      try {
        const prepared = await prepareIncomingPhoto(file)
        if (this.disposed) return
        if (this.queue.includes(file)) transfer.items.add(prepared)
      } catch (_) {
        if (this.disposed) return
        this.pushEvent("upload-preparation-error", {name: file.name})
      }
      this.queue = this.queue.filter(queued => queued !== file)
      this.report()
    }
    if (this.disposed) return
    if (transfer.files.length === 0) {
      this.preparing = false
      this.feeding = false
      this.report()
      this.feed()
      return
    }
    const input = this.el.querySelector('input[data-phx-upload-ref]')
    input.files = transfer.files
    this.synthetic = true
    input.dispatchEvent(new Event("change", {bubbles: true}))
    this.synthetic = false
    this.report()
  },
  destroyed() {
    this.disposed = true
    this.el.removeEventListener("input", this.onInput, true)
    this.el.removeEventListener("change", this.onChange, true)
  }
}
