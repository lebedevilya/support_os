import { Controller } from "@hotwired/stimulus"
import { renderStreamMessage } from "@hotwired/turbo-rails"

export default class extends Controller {
  static values = { url: String, interval: { type: Number, default: 3000 } }

  connect() {
    this.scheduleNext()
  }

  disconnect() {
    clearTimeout(this._timer)
  }

  scheduleNext() {
    this._timer = setTimeout(() => this.poll(), this.intervalValue)
  }

  async poll() {
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "text/vnd.turbo-stream.html" }
      })
      if (response.ok) {
        const html = await response.text()
        renderStreamMessage(html)
      }
    } catch (_e) {
      // network error — retry on next interval
      this.scheduleNext()
    }
  }
}
