import { Controller } from "@hotwired/stimulus"

/**
 * Loading Button Controller
 * 
 * Adds loading state to buttons during form submission.
 * Automatically clears loading state after Turbo navigation completes.
 * 
 * Usage:
 *   <button data-controller="loading-button" 
 *           data-action="click->loading-button#start">
 *     Submit
 *   </button>
 */
export default class extends Controller {
  static values = {
    timeout: { type: Number, default: 30000 }
  }

  connect() {
    // Listen for Turbo events to stop loading when navigation completes
    this.boundStop = this.stop.bind(this)
    document.addEventListener("turbo:render", this.boundStop)
    document.addEventListener("turbo:frame-render", this.boundStop)
    document.addEventListener("turbo:submit-end", this.handleSubmitEnd.bind(this))
  }

  disconnect() {
    document.removeEventListener("turbo:render", this.boundStop)
    document.removeEventListener("turbo:frame-render", this.boundStop)
    document.removeEventListener("turbo:submit-end", this.handleSubmitEnd.bind(this))
    this.clearTimeout()
  }

  start() {
    this.element.classList.add("is-loading")
    this.element.disabled = true
    
    // Safety timeout in case navigation doesn't trigger expected events
    this.timeoutId = setTimeout(() => {
      console.warn("Loading button timed out - clearing loading state")
      this.stop()
    }, this.timeoutValue)
  }

  stop() {
    this.clearTimeout()
    this.element.classList.remove("is-loading")
    this.element.disabled = false
  }

  handleSubmitEnd(event) {
    // Stop loading state after form submission completes
    if (event.target.contains(this.element) || event.target === this.element.closest("form")) {
      this.stop()
    }
  }

  clearTimeout() {
    if (this.timeoutId) {
      clearTimeout(this.timeoutId)
      this.timeoutId = null
    }
  }
}
