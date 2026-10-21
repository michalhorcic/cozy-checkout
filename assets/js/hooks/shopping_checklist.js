// A check belongs to an exact calculation, range and group, never to an ingredient alone.
export const ShoppingChecklist = {
  mounted() {
    this.memory = {}
    this.hideChecked = false
    this.onChange = event => {
      const input = event.target.closest('[data-shopping-check]')
      if (!input) return
      const checks = this.readChecks()
      if (input.checked) checks[input.dataset.shoppingCheck] = input.dataset.fingerprint
      else delete checks[input.dataset.shoppingCheck]
      this.writeChecks(checks)
      this.reconcile()
    }
    this.onClick = event => {
      if (!event.target.closest('[data-hide-checked]')) return
      this.hideChecked = !this.hideChecked
      this.reconcile()
    }
    this.onStorage = event => { if (event.key === this.key()) this.reconcile() }
    this.el.addEventListener('change', this.onChange)
    this.el.addEventListener('click', this.onClick)
    window.addEventListener('storage', this.onStorage)
    this.reconcile()
  },
  updated() { this.reconcile() },
  destroyed() {
    this.el.removeEventListener('change', this.onChange)
    this.el.removeEventListener('click', this.onClick)
    window.removeEventListener('storage', this.onStorage)
  },
  key() { return `cozy:kitchen-shopping:v1:${this.el.dataset.scope}` },
  readChecks() {
    try {
      const value = JSON.parse(localStorage.getItem(this.key()) || '{}')
      return value && typeof value === 'object' && !Array.isArray(value) ? value : {}
    } catch { return this.memory[this.key()] || {} }
  },
  writeChecks(checks) {
    this.memory[this.key()] = checks
    try { localStorage.setItem(this.key(), JSON.stringify(checks)) } catch { /* usable without storage */ }
  },
  reconcile() {
    if (this.scope !== this.el.dataset.scope) this.hideChecked = false
    this.scope = this.el.dataset.scope
    const signatures = JSON.parse(this.el.dataset.signatures || '{}')
    const stored = this.readChecks()
    const checks = Object.fromEntries(Object.entries(stored).filter(([id, signature]) => signatures[id] === signature))
    this.writeChecks(checks)
    this.el.querySelectorAll('[data-shopping-check]').forEach(input => {
      const checked = checks[input.dataset.shoppingCheck] === input.dataset.fingerprint
      input.checked = checked
      const row = input.closest('[data-shopping-row]')
      row.dataset.checked = checked ? 'true' : 'false'
      row.hidden = this.hideChecked && checked
    })
    this.el.querySelectorAll('[data-checked-count]').forEach(el => { el.textContent = Object.keys(checks).length })
    this.el.querySelectorAll('[data-hide-checked]').forEach(button => {
      button.setAttribute('aria-pressed', this.hideChecked ? 'true' : 'false')
      button.textContent = this.hideChecked ? 'Zobrazit i odškrtnuté' : 'Skrýt odškrtnuté'
    })
    const rows = [...this.el.querySelectorAll('[data-shopping-row]')]
    const done = this.el.querySelector('[data-all-checked]')
    if (done) done.hidden = !(rows.length > 0 && rows.every(row => row.hidden))
  }
}
