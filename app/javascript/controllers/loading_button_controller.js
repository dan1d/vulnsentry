import { Controller } from "@hotwired/stimulus"

/**
 * Loading Button Controller
 * 
 * Adds loading state to buttons during form submission.
 * 
 * Usage:
 *   <button data-controller="loading-button" 
 *           data-action="click->loading-button#start">
 *     Submit
 *   </button>
 */
export default class extends Controller {
  start() {
    this.element.classList.add("is-loading")
    this.element.disabled = true
  }

  stop() {
    this.element.classList.remove("is-loading")
    this.element.disabled = false
  }
}
