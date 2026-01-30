import { Controller } from "@hotwired/stimulus"

/**
 * AI Insights Controller
 * 
 * Handles interactivity for the AI insights panel.
 * Provides hover effects on confidence bars and expandable recommendation items.
 */
export default class extends Controller {
  static targets = ["recommendation", "expandButton"]

  connect() {
    // Bind handlers once to avoid creating new functions on each call
    this.boundShowTooltip = this.showTooltip.bind(this)
    this.boundHideTooltip = this.hideTooltip.bind(this)
    this.addTooltipHandlers()
  }

  disconnect() {
    // Clean up event listeners to prevent memory leaks
    this.removeTooltipHandlers()
  }

  addTooltipHandlers() {
    this.segments = this.element.querySelectorAll(".confidence-segment")
    this.segments.forEach(segment => {
      segment.addEventListener("mouseenter", this.boundShowTooltip)
      segment.addEventListener("mouseleave", this.boundHideTooltip)
    })
  }

  removeTooltipHandlers() {
    if (this.segments) {
      this.segments.forEach(segment => {
        segment.removeEventListener("mouseenter", this.boundShowTooltip)
        segment.removeEventListener("mouseleave", this.boundHideTooltip)
      })
    }
  }

  showTooltip(event) {
    const segment = event.target
    const title = segment.getAttribute("title")
    if (title) {
      segment.dataset.originalTitle = title
      // The native tooltip will show - we keep this for potential custom tooltips
    }
  }

  hideTooltip(event) {
    // Cleanup if needed
  }

  toggleRecommendation(event) {
    const item = event.currentTarget.closest(".ai-recommendation-item")
    if (item) {
      item.classList.toggle("is-expanded")
    }
  }
}
