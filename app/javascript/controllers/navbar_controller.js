import { Controller } from "@hotwired/stimulus"

/**
 * Navbar Controller
 * 
 * Handles mobile navbar burger menu toggle for Bulma.
 * Toggles the 'is-active' class on both the burger and the menu.
 */
export default class extends Controller {
  static targets = ["burger", "menu"]

  toggle() {
    this.burgerTarget.classList.toggle("is-active")
    this.menuTarget.classList.toggle("is-active")
    
    // Update ARIA attribute for accessibility
    const isExpanded = this.burgerTarget.classList.contains("is-active")
    this.burgerTarget.setAttribute("aria-expanded", isExpanded)
  }

  // Close menu when clicking outside
  closeOnClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  close() {
    this.burgerTarget.classList.remove("is-active")
    this.menuTarget.classList.remove("is-active")
    this.burgerTarget.setAttribute("aria-expanded", "false")
  }
}
