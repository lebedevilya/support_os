import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "textarea", "email"]

  play(event) {
    event.preventDefault()

    const prompt = event.currentTarget.dataset.scenarioPrompt
    if (!prompt) return
    const email = event.currentTarget.dataset.scenarioEmail

    this.textareaTarget.value = prompt
    this.textareaTarget.dispatchEvent(new Event("input", { bubbles: true }))

    if (this.hasEmailTarget && email) {
      this.emailTarget.value = email
      this.emailTarget.dispatchEvent(new Event("input", { bubbles: true }))
    }

    if (this.formTarget.reportValidity()) {
      this.formTarget.requestSubmit()
      return
    }

    const invalidField = this.formTarget.querySelector(":invalid")
    invalidField?.focus()
  }
}
