// Real-time Dashboard with WebSocket Support
// Connects to Action Cable and updates metrics in real-time

class RealtimeDashboard {
  constructor() {
    this.cable = null;
    this.metricsSubscription = null;
    this.auditLogsSubscription = null;
    this.connected = false;
    this.reconnectAttempts = 0;
    this.maxReconnectAttempts = 5;
  }

  // Initialize WebSocket connection
  connect() {
    // Create Action Cable consumer
    this.cable = ActionCable.createConsumer('/cable');

    // Subscribe to metrics channel
    this.subscribeToMetrics();

    // Subscribe to audit logs channel
    this.subscribeToAuditLogs();
  }

  // Subscribe to real-time metrics
  subscribeToMetrics() {
    this.metricsSubscription = this.cable.subscriptions.create('MetricsChannel', {
      connected: () => {
        console.log('✓ Connected to MetricsChannel');
        this.connected = true;
        this.reconnectAttempts = 0;
        this.updateConnectionStatus(true);

        // Request current stats
        this.metricsSubscription.send({
          action: 'get_current_stats'
        });

        // Start periodic updates
        this.metricsSubscription.send({
          action: 'start_periodic_updates'
        });
      },

      disconnected: () => {
        console.log('✗ Disconnected from MetricsChannel');
        this.connected = false;
        this.updateConnectionStatus(false);
        this.attemptReconnect();
      },

      received: (data) => {
        this.handleMetricsUpdate(data);
      }
    });
  }

  // Subscribe to real-time audit logs
  subscribeToAuditLogs() {
    this.auditLogsSubscription = this.cable.subscriptions.create('AuditLogsChannel', {
      connected: () => {
        console.log('✓ Connected to AuditLogsChannel');
      },

      disconnected: () => {
        console.log('✗ Disconnected from AuditLogsChannel');
      },

      received: (data) => {
        this.handleAuditLogUpdate(data);
      }
    });
  }

  // Handle incoming metrics updates
  handleMetricsUpdate(data) {
    console.log('Metrics update:', data);

    switch(data.type) {
      case 'connected':
        this.showNotification('success', data.message);
        break;

      case 'current_stats':
        this.updateStats(data.data);
        break;

      case 'request_logged':
        this.updateRequestMetrics(data.data);
        this.animateMetricUpdate('requests');
        break;

      case 'error_logged':
        this.updateErrorMetrics(data.data);
        this.animateMetricUpdate('errors');
        break;

      case 'alert':
        this.showAlert(data);
        break;

      default:
        console.log('Unknown metrics event:', data.type);
    }
  }

  // Handle incoming audit log updates
  handleAuditLogUpdate(data) {
    console.log('Audit log update:', data);

    if (data.type === 'audit_log_created') {
      this.addAuditLogRow(data.data);
    }
  }

  // Update dashboard statistics
  updateStats(stats) {
    // Update throughput
    if (stats.throughput !== undefined) {
      this.updateElement('live-throughput', stats.throughput.toFixed(2) + ' req/s');
    }

    // Update error rate
    if (stats.error_rate !== undefined) {
      this.updateElement('live-error-rate', stats.error_rate.toFixed(2) + '%');
    }

    // Update total requests
    if (stats.total_requests !== undefined) {
      this.updateElement('live-total-requests', stats.total_requests.toLocaleString());
    }

    // Update total errors
    if (stats.total_errors !== undefined) {
      this.updateElement('live-total-errors', stats.total_errors.toLocaleString());
    }

    // Update performance metrics
    if (stats.performance && stats.performance.avg) {
      this.updateElement('live-avg-response-time', stats.performance.avg.toFixed(2) + 'ms');
    }

    if (stats.performance && stats.performance.p95) {
      this.updateElement('live-p95-response-time', stats.performance.p95.toFixed(2) + 'ms');
    }
  }

  // Update request metrics
  updateRequestMetrics(data) {
    if (data.throughput !== undefined) {
      this.updateElement('live-throughput', data.throughput.toFixed(2) + ' req/s');
    }

    if (data.total_requests !== undefined) {
      this.updateElement('live-total-requests', data.total_requests.toLocaleString());
    }

    // Show recent request badge
    this.showRecentRequestBadge(data.method, data.status_code);
  }

  // Update error metrics
  updateErrorMetrics(data) {
    if (data.error_rate !== undefined) {
      this.updateElement('live-error-rate', data.error_rate.toFixed(2) + '%');
    }

    if (data.total_errors !== undefined) {
      this.updateElement('live-total-errors', data.total_errors.toLocaleString());
    }

    // Show error notification
    this.showErrorNotification(data.error_type, data.endpoint);
  }

  // Add new audit log row to table
  addAuditLogRow(log) {
    const table = document.querySelector('#recent-activity-table tbody');
    if (!table) return;

    // Create new row
    const row = document.createElement('tr');
    row.className = 'animate-fade-in';
    row.innerHTML = `
      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
        ${this.formatTimestamp(log.timestamp)}
      </td>
      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
        ${this.escapeHtml(log.event_type)}
      </td>
      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
        ${log.actor ? this.escapeHtml(log.actor.email) : 'System'}
      </td>
      <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
        ${this.escapeHtml(log.actor_ip || 'N/A')}
      </td>
    `;

    // Insert at top
    if (table.firstChild) {
      table.insertBefore(row, table.firstChild);
    } else {
      table.appendChild(row);
    }

    // Remove last row if more than 10
    const rows = table.querySelectorAll('tr');
    if (rows.length > 10) {
      table.removeChild(rows[rows.length - 1]);
    }

    // Highlight briefly
    setTimeout(() => row.classList.add('bg-green-50'), 100);
    setTimeout(() => row.classList.remove('bg-green-50'), 2000);
  }

  // Show alert notification
  showAlert(alert) {
    const alertClass = alert.level === 'error' ? 'bg-red-100 border-red-500 text-red-900' :
                       alert.level === 'warning' ? 'bg-yellow-100 border-yellow-500 text-yellow-900' :
                       'bg-blue-100 border-blue-500 text-blue-900';

    const alertHtml = `
      <div class="fixed top-4 right-4 z-50 ${alertClass} border-l-4 p-4 rounded shadow-lg max-w-md animate-slide-in-right">
        <div class="flex">
          <div class="flex-shrink-0">
            <svg class="h-5 w-5" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/>
            </svg>
          </div>
          <div class="ml-3">
            <p class="text-sm font-medium">${this.escapeHtml(alert.message)}</p>
          </div>
        </div>
      </div>
    `;

    const alertElement = document.createElement('div');
    alertElement.innerHTML = alertHtml;
    document.body.appendChild(alertElement.firstElementChild);

    // Auto-remove after 5 seconds
    setTimeout(() => {
      const alerts = document.querySelectorAll('.animate-slide-in-right');
      alerts.forEach(a => a.remove());
    }, 5000);
  }

  // Show notification
  showNotification(type, message) {
    console.log(`[${type.toUpperCase()}] ${message}`);
  }

  // Show recent request badge
  showRecentRequestBadge(method, statusCode) {
    const badge = document.getElementById('recent-request-badge');
    if (!badge) return;

    const color = statusCode < 300 ? 'green' : statusCode < 400 ? 'blue' : 'red';
    badge.className = `inline-flex items-center px-2 py-1 rounded text-xs font-medium bg-${color}-100 text-${color}-800 animate-pulse`;
    badge.textContent = `${method} ${statusCode}`;

    setTimeout(() => {
      badge.classList.remove('animate-pulse');
    }, 1000);
  }

  // Show error notification
  showErrorNotification(errorType, endpoint) {
    console.warn(`Error: ${errorType} at ${endpoint}`);
  }

  // Animate metric update
  animateMetricUpdate(metricType) {
    const element = document.getElementById(`${metricType}-card`);
    if (!element) return;

    element.classList.add('ring-2', 'ring-blue-400');
    setTimeout(() => {
      element.classList.remove('ring-2', 'ring-blue-400');
    }, 500);
  }

  // Update connection status indicator
  updateConnectionStatus(connected) {
    const indicator = document.getElementById('ws-status-indicator');
    if (!indicator) return;

    if (connected) {
      indicator.className = 'h-3 w-3 rounded-full bg-green-500 animate-pulse';
      indicator.title = 'Connected (Live updates enabled)';
    } else {
      indicator.className = 'h-3 w-3 rounded-full bg-red-500';
      indicator.title = 'Disconnected (Reconnecting...)';
    }
  }

  // Attempt to reconnect
  attemptReconnect() {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      console.error('Max reconnection attempts reached');
      return;
    }

    this.reconnectAttempts++;
    const delay = Math.min(1000 * Math.pow(2, this.reconnectAttempts), 30000);

    console.log(`Attempting to reconnect in ${delay}ms (attempt ${this.reconnectAttempts}/${this.maxReconnectAttempts})`);

    setTimeout(() => {
      this.connect();
    }, delay);
  }

  // Update element text content
  updateElement(id, value) {
    const element = document.getElementById(id);
    if (element) {
      element.textContent = value;
    }
  }

  // Format timestamp
  formatTimestamp(timestamp) {
    const date = new Date(timestamp);
    return date.toLocaleTimeString();
  }

  // Escape HTML to prevent XSS
  escapeHtml(text) {
    if (!text) return '';
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  // Disconnect
  disconnect() {
    if (this.metricsSubscription) {
      this.metricsSubscription.unsubscribe();
    }
    if (this.auditLogsSubscription) {
      this.auditLogsSubscription.unsubscribe();
    }
    this.connected = false;
  }
}

// Initialize dashboard when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  // Only initialize if we're on the dashboard page
  if (document.getElementById('realtime-dashboard')) {
    window.realtimeDashboard = new RealtimeDashboard();
    window.realtimeDashboard.connect();

    // Disconnect when page unloads
    window.addEventListener('beforeunload', () => {
      window.realtimeDashboard.disconnect();
    });
  }
});
