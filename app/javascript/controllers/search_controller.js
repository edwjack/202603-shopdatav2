import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]

  connect() {
    this.timer = null
  }

  debounce() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      this.element.requestSubmit()
    }, 300)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
