import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["openButton", "panel"]

  open() {
    this.panelTarget.classList.remove("hidden")
    this.openButtonTarget.classList.add("hidden")
  }

  close() {
    this.panelTarget.classList.add("hidden")
    this.openButtonTarget.classList.remove("hidden")
  }
}
