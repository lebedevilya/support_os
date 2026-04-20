import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["openButton", "panel", "customerEmail"]

  connect() {
    this.syncCustomerEmail = this.syncCustomerEmail.bind(this)
    document.addEventListener("turbo:frame-load", this.syncCustomerEmail)
    this.syncCustomerEmail()
  }

  disconnect() {
    document.removeEventListener("turbo:frame-load", this.syncCustomerEmail)
  }

  open() {
    this.panelTarget.classList.remove("hidden")
    this.openButtonTarget.classList.add("hidden")
  }

  close() {
    this.panelTarget.classList.add("hidden")
    this.openButtonTarget.classList.remove("hidden")
  }

  syncCustomerEmail() {
    if (!this.hasCustomerEmailTarget) return

    const frame = this.element.querySelector("#support_widget")
    const email = frame?.dataset.customerEmail?.trim()

    this.customerEmailTarget.textContent = email || ""
    this.customerEmailTarget.classList.toggle("hidden", !email)
  }
}
