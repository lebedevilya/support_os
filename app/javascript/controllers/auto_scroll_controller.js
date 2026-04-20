import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["viewport"]

  connect() {
    this.scrollToBottom()
  }

  scrollToBottom() {
    if (!this.hasViewportTarget) return

    requestAnimationFrame(() => {
      this.viewportTarget.scrollTop = this.viewportTarget.scrollHeight
    })
  }
}
