import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "button"]

  connect() {
    this.collapsed = true
  }

  toggle() {
    this.collapsed = !this.collapsed
    if (this.collapsed) {
      this.contentTarget.style.maxHeight = "4.5rem"
      this.contentTarget.style.overflow = "hidden"
      this.buttonTarget.textContent = "Show more"
    } else {
      this.contentTarget.style.maxHeight = "none"
      this.contentTarget.style.overflow = "visible"
      this.buttonTarget.textContent = "Show less"
    }
  }
}
