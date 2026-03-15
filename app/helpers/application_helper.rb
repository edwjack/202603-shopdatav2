module ApplicationHelper
  def sidebar_link(label, path, icon)
    active = current_page?(path)
    css = active ? "bg-gray-800 text-white" : "text-gray-300 hover:bg-gray-700 hover:text-white"
    content_tag(:li) do
      link_to path, class: "group flex gap-x-3 rounded-md p-2 text-sm font-semibold #{css}" do
        sidebar_icon(icon) + content_tag(:span, label)
      end
    end
  end

  def sidebar_icon(name)
    icons = {
      "home" => '<svg class="h-6 w-6 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="m2.25 12 8.954-8.955a1.126 1.126 0 0 1 1.591 0L21.75 12M4.5 9.75v10.125c0 .621.504 1.125 1.125 1.125H9.75v-4.875c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125V21h4.125c.621 0 1.125-.504 1.125-1.125V9.75M8.25 21h8.25"/></svg>',
      "folder" => '<svg class="h-6 w-6 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M2.25 12.75V12A2.25 2.25 0 0 1 4.5 9.75h15A2.25 2.25 0 0 1 21.75 12v.75m-8.69-6.44-2.12-2.12a1.5 1.5 0 0 0-1.061-.44H4.5A2.25 2.25 0 0 0 2.25 6v12a2.25 2.25 0 0 0 2.25 2.25h15A2.25 2.25 0 0 0 21.75 18V9a2.25 2.25 0 0 0-2.25-2.25h-5.379a1.5 1.5 0 0 1-1.06-.44Z"/></svg>',
      "star" => '<svg class="h-6 w-6 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M11.48 3.499a.562.562 0 0 1 1.04 0l2.125 5.111a.563.563 0 0 0 .475.345l5.518.442c.499.04.701.663.321.988l-4.204 3.602a.563.563 0 0 0-.182.557l1.285 5.385a.562.562 0 0 1-.84.61l-4.725-2.885a.562.562 0 0 0-.586 0L6.982 20.54a.562.562 0 0 1-.84-.61l1.285-5.386a.562.562 0 0 0-.182-.557l-4.204-3.602a.562.562 0 0 1 .321-.988l5.518-.442a.563.563 0 0 0 .475-.345L11.48 3.5Z"/></svg>',
      "box" => '<svg class="h-6 w-6 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="m21 7.5-9-5.25L3 7.5m18 0-9 5.25m9-5.25v9l-9 5.25M3 7.5l9 5.25M3 7.5v9l9 5.25m0-9v9"/></svg>',
      "clock" => '<svg class="h-6 w-6 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6h4.5m4.5 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"/></svg>'
    }
    (icons[name] || "").html_safe
  end

  def score_color(score)
    case score
    when 8..10 then "text-green-600 bg-green-50"
    when 6..7 then "text-blue-600 bg-blue-50"
    when 4..5 then "text-yellow-600 bg-yellow-50"
    else "text-red-600 bg-red-50"
    end
  end

  def status_badge(status)
    colors = {
      'pending'    => 'bg-yellow-100 text-yellow-800',
      'approved'   => 'bg-green-100 text-green-800',
      'rejected'   => 'bg-red-100 text-red-800',
      'on_hold'    => 'bg-gray-100 text-gray-800',
      'tracking'   => 'bg-blue-100 text-blue-800',
      'sourcing'   => 'bg-purple-100 text-purple-800',
      'completed'  => 'bg-green-100 text-green-800',
      'publishing' => 'bg-blue-100 text-blue-800',
      'draft'      => 'bg-gray-100 text-gray-800',
      'failed'     => 'bg-red-100 text-red-800',
      'synced'     => 'bg-green-100 text-green-800',
      'collected'  => 'bg-teal-100 text-teal-800'
    }
    css = colors[status.to_s] || 'bg-gray-100 text-gray-800'
    content_tag(:span, status.to_s.humanize, class: "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium #{css}")
  end

  def format_date(datetime)
    datetime&.strftime("%Y-%m-%d %H:%M")
  end
end
