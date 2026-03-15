import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "reason"]

  open() {
    this.dialogTarget.classList.remove("hidden")
    if (this.hasReasonTarget) {
      this.reasonTarget.focus()
    }
  }

  close() {
    this.dialogTarget.classList.add("hidden")
    if (this.hasReasonTarget) {
      this.reasonTarget.value = ""
    }
  }

  submit(event) {
    if (this.hasReasonTarget) {
      const reason = this.reasonTarget.value.trim()
      if (reason.length < 10) {
        event.preventDefault()
        alert("Please enter a reason of at least 10 characters.")
        this.reasonTarget.focus()
      }
    }
  }
}
