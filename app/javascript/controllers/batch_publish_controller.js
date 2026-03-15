import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["selectAll", "checkbox", "toolbar", "count"]

  toggleAll() {
    const checked = this.selectAllTarget.checked
    this.checkboxTargets.forEach(cb => cb.checked = checked)
    this.updateCount()
  }

  updateCount() {
    const selected = this.checkboxTargets.filter(cb => cb.checked).length
    this.toolbarTarget.style.display = selected > 0 ? "flex" : "none"
    this.countTarget.textContent = `${selected} selected`
  }
}
