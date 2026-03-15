class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def paginate(scope, per_page: 25)
    page = (params[:page] || 1).to_i
    page = 1 if page < 1
    total = scope.count(:all)
    total_pages = (total.to_f / per_page).ceil
    total_pages = 1 if total_pages < 1
    page = total_pages if page > total_pages
    items = scope.offset((page - 1) * per_page).limit(per_page).to_a
    has_next = page < total_pages
    [items, page, has_next, total, total_pages]
  end
end
