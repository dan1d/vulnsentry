import { Controller } from "@hotwired/stimulus"

/**
 * Dashboard Stats Controller
 * 
 * Provides live updates for dashboard statistics using polling.
 * Connects to a stats endpoint and updates stat cards in real-time.
 * 
 * Usage:
 *   <div data-controller="dashboard-stats" 
 *        data-dashboard-stats-url-value="/admin/dashboard/stats"
 *        data-dashboard-stats-interval-value="30000">
 *     <div data-dashboard-stats-target="stat" data-stat-id="open_prs">...</div>
 *   </div>
 */
export default class extends Controller {
  static targets = ["stat", "refreshButton"]
  static values = {
    url: String,
    interval: { type: Number, default: 30000 } // 30 seconds default
  }

  connect() {
    this.startPolling()
  }

  disconnect() {
    this.stopPolling()
  }

  startPolling() {
    if (this.hasUrlValue) {
      this.poll()
      this.pollTimer = setInterval(() => this.poll(), this.intervalValue)
    }
  }

  stopPolling() {
    if (this.pollTimer) {
      clearInterval(this.pollTimer)
    }
  }

  async poll() {
    if (!this.hasUrlValue) return

    try {
      const response = await fetch(this.urlValue, {
        headers: {
          "Accept": "application/json",
          "X-Requested-With": "XMLHttpRequest"
        }
      })

      if (response.ok) {
        const data = await response.json()
        this.updateStats(data)
      }
    } catch (error) {
      console.warn("Failed to fetch dashboard stats:", error)
    }
  }

  updateStats(data) {
    this.statTargets.forEach(statElement => {
      const statId = statElement.dataset.statId
      if (statId && data[statId] !== undefined) {
        const valueElement = statElement.querySelector(".stat-value")
        const trendElement = statElement.querySelector(".stat-trend")
        
        if (valueElement) {
          const oldValue = parseInt(valueElement.textContent, 10)
          const newValue = data[statId].value
          
          if (oldValue !== newValue) {
            valueElement.textContent = newValue
            this.animateChange(statElement, newValue > oldValue)
          }
        }

        if (data[statId].trend !== undefined) {
          this.updateTrend(statElement, data[statId].trend, data[statId].trend_period)
        }
      }
    })
  }

  updateTrend(statElement, trend, period) {
    let trendElement = statElement.querySelector(".stat-trend")
    
    if (trend === 0) {
      if (trendElement) trendElement.remove()
      return
    }

    const isPositive = trend > 0
    const trendClass = isPositive ? "is-positive" : "is-negative"
    const arrow = isPositive 
      ? '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="18 15 12 9 6 15"/></svg>'
      : '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="6 9 12 15 18 9"/></svg>'

    const trendHTML = `
      <div class="stat-trend ${trendClass}">
        <span class="trend-icon">${arrow}</span>
        <span class="trend-value">${isPositive ? '+' : ''}${trend}</span>
        ${period ? `<span class="trend-period">${period}</span>` : ''}
      </div>
    `

    if (trendElement) {
      trendElement.outerHTML = trendHTML
    } else {
      const container = statElement.querySelector(".stat-value-container")
      if (container) {
        container.insertAdjacentHTML("beforeend", trendHTML)
      }
    }
  }

  animateChange(element, isIncrease) {
    element.classList.remove("stat-pulse-up", "stat-pulse-down")
    // Trigger reflow to restart animation
    void element.offsetWidth
    element.classList.add(isIncrease ? "stat-pulse-up" : "stat-pulse-down")
    
    setTimeout(() => {
      element.classList.remove("stat-pulse-up", "stat-pulse-down")
    }, 600)
  }

  refresh() {
    if (this.hasRefreshButtonTarget) {
      this.refreshButtonTarget.classList.add("is-loading")
    }
    
    this.poll().finally(() => {
      if (this.hasRefreshButtonTarget) {
        this.refreshButtonTarget.classList.remove("is-loading")
      }
    })
  }
}
