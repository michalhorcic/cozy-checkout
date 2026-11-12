const storageKey = "cozy-design"

function syncSwitchers() {
  const theme = document.documentElement.dataset.theme
  document.querySelectorAll("[data-design-theme]").forEach(button => {
    button.setAttribute("aria-pressed", String(button.dataset.designTheme === theme))
  })
}

function applyTheme(theme) {
  document.documentElement.dataset.theme = theme === "light" ? "light" : "noir"
  syncSwitchers()
}

// Controller-rendered pages do not mount LiveView hooks.
syncSwitchers()

// Delegation also covers controls replaced by LiveView navigation.
document.addEventListener("click", event => {
  const button = event.target.closest("button[data-design-theme]")
  if (!button) return
  applyTheme(button.dataset.designTheme)
  try {
    localStorage.setItem(storageKey, document.documentElement.dataset.theme)
  } catch (_) {
    // The in-page switch still works in browsers that disallow local storage.
  }
})

window.addEventListener("storage", event => {
  if (event.key === storageKey || event.key === null) applyTheme(event.newValue)
})

// Return focus to the disclosure before hiding a focused mobile navigation link.
document.addEventListener("keydown", event => {
  if (event.key !== "Escape") return
  const navigation = event.target.closest("#admin-mobile-navigation, #food-mobile-navigation")
  if (navigation?.open) navigation.querySelector("summary").focus()
}, true)

export const DesignSwitcher = {
  mounted() { syncSwitchers() },
  updated() { syncSwitchers() }
}
