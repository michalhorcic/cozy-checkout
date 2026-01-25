// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/cozy_checkout"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

// Custom hooks
const Hooks = {
  SwipeToDelete: {
    mounted() {
      let startX = 0
      let currentX = 0
      let isDragging = false
      const threshold = 100 // pixels to swipe before deleting
      
      const content = this.el.querySelector('.swipe-content')
      const deleteButton = this.el.querySelector('.swipe-delete-bg')
      
      if (!content || !deleteButton) return
      
      const handleTouchStart = (e) => {
        startX = e.touches[0].clientX
        isDragging = true
        content.style.transition = 'none'
      }
      
      const handleTouchMove = (e) => {
        if (!isDragging) return
        
        currentX = e.touches[0].clientX
        const diffX = startX - currentX
        
        // Only allow left swipe
        if (diffX > 0) {
          const translateX = Math.min(diffX, threshold * 1.5)
          content.style.transform = `translateX(-${translateX}px)`
        }
      }
      
      const handleTouchEnd = () => {
        if (!isDragging) return
        
        isDragging = false
        const diffX = startX - currentX
        
        content.style.transition = 'transform 0.3s ease'
        
        if (diffX > threshold) {
          // Delete the item or group
          const itemId = this.el.dataset.itemId
          const itemIds = this.el.dataset.itemIds
          
          if (itemIds) {
            // It's a group - delete all items
            this.pushEvent("delete_group", {item_ids: itemIds})
          } else if (itemId) {
            // It's a single item
            this.pushEvent("delete_item", {item_id: itemId})
          }
          
          // Animate out
          content.style.transform = `translateX(-${this.el.offsetWidth}px)`
          setTimeout(() => {
            this.el.style.opacity = '0'
            this.el.style.transform = 'scaleY(0)'
            this.el.style.transition = 'all 0.3s ease'
          }, 300)
        } else {
          // Reset position
          content.style.transform = 'translateX(0)'
        }
        
        startX = 0
        currentX = 0
      }
      
      this.el.addEventListener('touchstart', handleTouchStart, {passive: true})
      this.el.addEventListener('touchmove', handleTouchMove, {passive: true})
      this.el.addEventListener('touchend', handleTouchEnd)
      
      this.handleTouchStart = handleTouchStart
      this.handleTouchMove = handleTouchMove
      this.handleTouchEnd = handleTouchEnd
    },
    
    destroyed() {
      if (this.handleTouchStart) {
        this.el.removeEventListener('touchstart', this.handleTouchStart)
        this.el.removeEventListener('touchmove', this.handleTouchMove)
        this.el.removeEventListener('touchend', this.handleTouchEnd)
      }
    }
  },

  UnitAmountSelector: {
    mounted() {
      // Add click handlers to quick select buttons
      const buttons = this.el.querySelectorAll('[data-unit-amount]')
      const input = this.el.querySelector('#unit-amount-input')
      
      if (!input) return
      
      buttons.forEach(button => {
        button.addEventListener('click', (e) => {
          const amount = e.currentTarget.dataset.unitAmount
          // Directly add the item with this amount
          this.pushEvent("quick_add_unit_amount", {unit_amount: amount})
        })
      })
    }
  },
  
  ProductUnitTracker: {
    mounted() {
      this.handleProductChange = () => {
        const productId = this.el.value
        const products = JSON.parse(this.el.dataset.products || '[]')
        const product = products.find(p => p.id === productId)
        
        const container = document.getElementById('unit-amount-container')
        const input = document.getElementById('unit-amount-input')
        const label = document.getElementById('unit-label')
        const helpText = document.getElementById('unit-help-text')
        
        if (product && product.unit) {
          container.classList.remove('hidden')
          label.textContent = `(${product.unit})`
          input.required = true
          
          // Handle default amounts
          if (product.default_amounts) {
            try {
              const amounts = JSON.parse(product.default_amounts)
              if (Array.isArray(amounts) && amounts.length > 0) {
                helpText.textContent = `Suggested: ${amounts.join(', ')}`
                // Optionally set first value as default
                if (input.value === '') {
                  input.value = amounts[0]
                }
              } else {
                helpText.textContent = ''
              }
            } catch (e) {
              helpText.textContent = ''
            }
          } else {
            helpText.textContent = ''
          }
        } else {
          container.classList.add('hidden')
          input.required = false
          input.value = ''
          helpText.textContent = ''
        }
      }
      
      this.el.addEventListener('change', this.handleProductChange)
    },
    
    destroyed() {
      this.el.removeEventListener('change', this.handleProductChange)
    }
  },

  // Keep-alive hook to prevent socket disconnects during idle periods
  KeepAlive: {
    mounted() {
      // Send a heartbeat every 25 seconds to keep connection alive
      this.interval = setInterval(() => {
        this.pushEvent("heartbeat", {})
      }, 25000)
    },
    destroyed() {
      clearInterval(this.interval)
    }
  }
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
  heartbeatIntervalMs: 15000,  // Send heartbeat every 15 seconds (default: 30s)
  timeout: 20000                // Wait 20s for server response (default: 10s)
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// For POS tablets - prevent sleep and maintain connection
if (/pos/.test(window.location.pathname)) {
  // Send a ping every 30 seconds to keep connection alive
  setInterval(() => {
    if (liveSocket.isConnected()) {
      // Touch a DOM element to prevent sleep
      document.body.style.transform = 'translateZ(0)'
      setTimeout(() => {
        document.body.style.transform = ''
      }, 100)
    }
  }, 30000)
  
  // Request wake lock API (keeps screen on)
  if ('wakeLock' in navigator) {
    let wakeLock = null
    const requestWakeLock = async () => {
      try {
        wakeLock = await navigator.wakeLock.request('screen')
        wakeLock.addEventListener('release', () => {
          console.log('Screen Wake Lock released')
        })
        console.log('Screen Wake Lock acquired')
      } catch (err) {
        console.error('Wake Lock error:', err)
      }
    }
    requestWakeLock()
    
    // Re-acquire wake lock if page becomes visible again
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') {
        requestWakeLock()
      }
    })
  }
}

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

