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
    this.addTooltipHandlers()
  }

  addTooltipHandlers() {
    const segments = this.element.querySelectorAll(".confidence-segment")
    segments.forEach(segment => {
      segment.addEventListener("mouseenter", this.showTooltip.bind(this))
      segment.addEventListener("mouseleave", this.hideTooltip.bind(this))
    })
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
