module.exports = {
  content: [
    './app/views/**/*.html.erb',
    './app/helpers/**/*.rb',
    './app/assets/stylesheets/**/*.css',
    './app/javascript/**/*.js'
  ],
  safelist: [
    'badge', 'badge-success', 'badge-info', 'badge-error', 'badge-warning', 'badge-outline', 'badge-lg', 'badge-sm', 'badge-xs', 'badge-ghost',
    'btn', 'btn-primary', 'btn-secondary', 'btn-accent', 'btn-ghost', 'btn-circle', 'btn-sm', 'btn-lg',
    'navbar', 'navbar-start', 'navbar-center', 'navbar-end',
    'menu', 'menu-horizontal', 'menu-sm', 'menu-title',
    'dropdown', 'dropdown-end', 'dropdown-content',
    'tabs', 'tabs-boxed', 'tab', 'tab-active',
    'alert', 'alert-info', 'alert-success', 'alert-error', 'alert-warning',
    'card', 'card-body', 'card-title', 'card-actions',
    'divider',
    'avatar', 'placeholder',
    'stat', 'stat-title', 'stat-value', 'stat-desc',
    'progress', 'progress-primary', 'progress-success', 'progress-error',
    'table', 'table-zebra', 'table-sm',
  ],
  plugins: [
    require('daisyui')
  ],
  daisyui: {
    themes: ["light", "dark", "cupcake"],
    styled: true,
    base: true,
    utils: true,
  }
}
