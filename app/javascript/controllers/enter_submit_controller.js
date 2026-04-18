import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  submitOnEnter(event) {
    if (event.key !== "Enter" || event.shiftKey) return

    event.preventDefault()
    this.element.form?.requestSubmit()
  }
}
