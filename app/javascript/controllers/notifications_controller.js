import { Controller } from "@hotwired/stimulus"

/**
 * Notifications Controller
 * 
 * Manages browser notifications for VulnSentry alerts.
 * Uses the Web Notifications API (Chrome, Firefox, Safari, Edge).
 * 
 * Usage:
 *   <div data-controller="notifications"
 *        data-notifications-enabled-value="true">
 *     <button data-action="click->notifications#requestPermission">
 *       Enable Notifications
 *     </button>
 *   </div>
 */
export default class extends Controller {
  static targets = ["permissionButton", "status"]
  static values = {
    enabled: { type: Boolean, default: true }
  }

  connect() {
    this.updatePermissionStatus()
  }

  /**
   * Check if notifications are supported and get current permission status
   */
  get isSupported() {
    return "Notification" in window
  }

  get permission() {
    return this.isSupported ? Notification.permission : "denied"
  }

  /**
   * Request notification permission from the user
   */
  async requestPermission() {
    if (!this.isSupported) {
      console.warn("Browser notifications not supported")
      return
    }

    try {
      const permission = await Notification.requestPermission()
      this.updatePermissionStatus()
      
      if (permission === "granted") {
        this.showNotification({
          title: "VulnSentry Notifications Enabled",
          body: "You'll be notified when new security advisories are found.",
          icon: "/icon.png",
          tag: "vulnsentry-enabled"
        })
      }
    } catch (error) {
      console.error("Failed to request notification permission:", error)
    }
  }

  /**
   * Update UI to reflect current permission status
   */
  updatePermissionStatus() {
    if (this.hasStatusTarget) {
      const status = this.permission
      this.statusTarget.textContent = status
      this.statusTarget.dataset.status = status
    }

    if (this.hasPermissionButtonTarget) {
      if (this.permission === "granted") {
        this.permissionButtonTarget.classList.add("is-hidden")
      } else if (this.permission === "denied") {
        this.permissionButtonTarget.disabled = true
        this.permissionButtonTarget.textContent = "Notifications Blocked"
      }
    }
  }

  /**
   * Show a browser notification
   * @param {Object} options - Notification options
   * @param {string} options.title - Notification title
   * @param {string} options.body - Notification body text
   * @param {string} options.icon - Icon URL
   * @param {string} options.tag - Unique tag to prevent duplicates
   * @param {string} options.url - URL to open when clicked
   */
  showNotification({ title, body, icon = "/icon.png", tag, url }) {
    if (!this.isSupported || this.permission !== "granted" || !this.enabledValue) {
      return
    }

    const notification = new Notification(title, {
      body,
      icon,
      tag,
      badge: "/icon.png",
      requireInteraction: true,
      silent: false
    })

    if (url) {
      notification.onclick = () => {
        window.focus()
        window.location.href = url
        notification.close()
      }
    }

    // Auto-close after 10 seconds
    setTimeout(() => notification.close(), 10000)
  }

  /**
   * Notify about new advisories found
   * Called from other controllers when advisories are detected
   */
  notifyAdvisories(count, gemNames = []) {
    const gemList = gemNames.slice(0, 3).join(", ")
    const moreText = gemNames.length > 3 ? ` and ${gemNames.length - 3} more` : ""
    
    this.showNotification({
      title: `🚨 ${count} New Advisory${count > 1 ? "ies" : ""} Found`,
      body: gemList ? `Affected gems: ${gemList}${moreText}` : "Check the dashboard for details.",
      tag: "vulnsentry-advisory",
      url: "/admin/advisories"
    })
  }

  /**
   * Notify about sync completion
   */
  notifySyncComplete(advisoriesFound) {
    if (advisoriesFound > 0) {
      this.showNotification({
        title: `⚠️ Sync Complete: ${advisoriesFound} Advisory${advisoriesFound > 1 ? "ies" : ""} Found`,
        body: "New security vulnerabilities detected. Review required.",
        tag: "vulnsentry-sync",
        url: "/admin/patch_bundles?state=ready_for_review"
      })
    }
  }

  /**
   * Notify about evaluation results with warnings
   */
  notifyEvaluationWarning(message) {
    this.showNotification({
      title: "⚠️ VulnSentry Alert",
      body: message,
      tag: "vulnsentry-warning",
      url: "/admin/system_events"
    })
  }
}
