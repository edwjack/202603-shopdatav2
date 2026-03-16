import { Controller } from "@hotwired/stimulus"

// Manages per-job category dropdown + run button state in the Jobs UI.
// Usage:
//   data-controller="job-runner"
//   data-job-runner-job-class-value="AmazonBsrCollectorJob"
export default class extends Controller {
  static targets = ["categorySelect", "runButton", "runAllButton"]
  static values = { jobClass: String }

  connect() {
    this.updateButtonState()
  }

  // Called when category dropdown changes
  categoryChanged() {
    this.updateButtonState()
  }

  // Run with selected category (or no category if none selected)
  run(event) {
    event.preventDefault()
    const categoryId = this.hasCategorySelectTarget
      ? this.categorySelectTarget.value
      : null
    const categoryName = this.hasCategorySelectTarget && categoryId
      ? this.categorySelectTarget.options[this.categorySelectTarget.selectedIndex]?.text
      : null

    const label = categoryName ? `${this.jobClassValue} for ${categoryName}` : this.jobClassValue
    if (!confirm(`Enqueue ${label}?`)) return

    this.submitJob(categoryId)
  }

  // Run all categories (no category_id)
  runAll(event) {
    event.preventDefault()
    if (!confirm(`Enqueue ${this.jobClassValue} for ALL categories?`)) return
    this.submitJob(null)
  }

  submitJob(categoryId) {
    const form = document.createElement("form")
    form.method = "post"
    form.action = this.element.dataset.jobRunnerUrlValue || "/jobs/run"

    const csrf = document.querySelector("meta[name='csrf-token']")
    if (csrf) {
      const csrfInput = document.createElement("input")
      csrfInput.type = "hidden"
      csrfInput.name = "authenticity_token"
      csrfInput.value = csrf.getAttribute("content")
      form.appendChild(csrfInput)
    }

    const jobInput = document.createElement("input")
    jobInput.type = "hidden"
    jobInput.name = "job_class"
    jobInput.value = this.jobClassValue
    form.appendChild(jobInput)

    if (categoryId) {
      const catInput = document.createElement("input")
      catInput.type = "hidden"
      catInput.name = "category_id"
      catInput.value = categoryId
      form.appendChild(catInput)
    }

    document.body.appendChild(form)
    form.submit()
  }

  updateButtonState() {
    if (!this.hasRunButtonTarget) return
    // Run button is always enabled; label updates based on selection
    const categoryId = this.hasCategorySelectTarget
      ? this.categorySelectTarget.value
      : null
    if (categoryId) {
      this.runButtonTarget.textContent = "Run"
      this.runButtonTarget.disabled = false
    } else {
      this.runButtonTarget.textContent = "Run (select category)"
      this.runButtonTarget.disabled = false
    }
  }
}
