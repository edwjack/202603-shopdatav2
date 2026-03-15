import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["bar"]

  connect() {
    this.barTargets.forEach(bar => this.updateBar(bar))
  }

  updateBar(bar) {
    const score = parseFloat(bar.dataset.score) || 0
    const pct = Math.min(Math.max(score / 10 * 100, 0), 100)
    bar.style.width = pct + "%"
    bar.className = bar.className.replace(/bg-\w+-\d+/g, "")
    if (score >= 8) {
      bar.classList.add("bg-green-500")
    } else if (score >= 6) {
      bar.classList.add("bg-blue-500")
    } else if (score >= 4) {
      bar.classList.add("bg-yellow-500")
    } else {
      bar.classList.add("bg-red-500")
    }
  }
}
