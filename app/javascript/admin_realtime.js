// Admin Real-time Metrics via WebSocket
// Connects to AdminMetricsChannel and handles real-time updates

import consumer from "./channels/consumer"

document.addEventListener('DOMContentLoaded', () => {
  // Only initialize on admin pages
  if (!document.body.classList.contains('admin-layout')) return;

  const adminMetricsSubscription = consumer.subscriptions.create("AdminMetricsChannel", {
    connected() {
      console.log('[Admin Metrics] Connected to WebSocket');
      this.showConnectionStatus('connected');
    },

    disconnected() {
      console.log('[Admin Metrics] Disconnected from WebSocket');
      this.showConnectionStatus('disconnected');
    },

    received(data) {
      console.log('[Admin Metrics] Received:', data);

      switch(data.type) {
        case 'health_status':
          this.updateHealthStatus(data.data);
          break;
        case 'api_disabled':
          this.showAlert('danger', `API "${data.data.api_name}" has been DISABLED`, data.data);
          this.playAlertSound();
          break;
        case 'api_enabled':
          this.showAlert('success', `API "${data.data.api_name}" has been enabled`, data.data);
          break;
        case 'ip_blocked':
          this.showAlert('warning', `IP ${data.data.ip_address} has been BLOCKED`, data.data);
          this.updateBlockedIPCount();
          this.playAlertSound();
          break;
        case 'ip_unblocked':
          this.showAlert('info', `IP ${data.data.ip_address} has been unblocked`, data.data);
          this.updateBlockedIPCount();
          break;
        case 'policy_created':
          this.showAlert('info', `New rate limit policy created for ${data.data.tier} tier`, data.data);
          break;
        case 'policy_updated':
          this.showAlert('warning', `Rate limit policy updated for ${data.data.tier} tier`, data.data);
          this.playAlertSound();
          break;
        case 'tier_changed':
          this.showAlert('info', `User tier changed: ${data.data.user_email} (${data.data.old_tier} → ${data.data.new_tier})`, data.data);
          break;
        case 'critical_event':
          this.showAlert('danger', `CRITICAL: ${data.data.message}`, data.data);
          this.playAlertSound();
          this.flashCritical();
          break;
      }
    },

    // Update health status indicators on overview page
    updateHealthStatus(health) {
      // Update gateway status
      const gatewayEl = document.querySelector('[data-health-gateway]');
      if (gatewayEl) {
        gatewayEl.className = `badge badge-lg ${this.healthBadgeClass(health.gateway)}`;
        gatewayEl.textContent = health.gateway.toUpperCase();
      }

      // Update Redis status
      const redisEl = document.querySelector('[data-health-redis]');
      if (redisEl) {
        redisEl.className = `badge badge-lg ${this.healthBadgeClass(health.redis)}`;
        redisEl.textContent = health.redis.toUpperCase();
      }

      // Update error rate
      const errorRateEl = document.querySelector('[data-health-error-rate]');
      if (errorRateEl) {
        errorRateEl.textContent = `${health.error_rate}%`;
        errorRateEl.className = this.errorRateClass(health.error_rate);
      }

      // Update blocked IPs count
      const blockedIPsEl = document.querySelector('[data-health-blocked-ips]');
      if (blockedIPsEl) {
        blockedIPsEl.textContent = health.blocked_ips;
      }
    },

    // Show connection status indicator
    showConnectionStatus(status) {
      const indicator = document.getElementById('ws-connection-status');
      if (!indicator) return;

      if (status === 'connected') {
        indicator.innerHTML = '<span class="text-green-600 text-xs">● Live</span>';
      } else {
        indicator.innerHTML = '<span class="text-red-600 text-xs">● Disconnected</span>';
      }
    },

    // Show floating alert notification
    showAlert(type, message, data) {
      const alertContainer = document.getElementById('admin-alerts');
      if (!alertContainer) return;

      const alertColors = {
        success: 'alert-success',
        info: 'alert-info',
        warning: 'alert-warning',
        danger: 'alert-error'
      };

      const alert = document.createElement('div');
      alert.className = `alert ${alertColors[type]} shadow-lg mb-2`;
      alert.innerHTML = `
        <div>
          <svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
          </svg>
          <div>
            <strong>${message}</strong>
            <div class="text-xs mt-1">${new Date(data.timestamp).toLocaleTimeString()}</div>
          </div>
        </div>
        <button class="btn btn-sm btn-ghost" onclick="this.parentElement.remove()">✕</button>
      `;

      alertContainer.appendChild(alert);

      // Auto-remove after 10 seconds
      setTimeout(() => {
        alert.remove();
      }, 10000);
    },

    // Play alert sound for critical events
    playAlertSound() {
      // Simple beep using Web Audio API
      try {
        const audioContext = new (window.AudioContext || window.webkitAudioContext)();
        const oscillator = audioContext.createOscillator();
        const gainNode = audioContext.createGain();

        oscillator.connect(gainNode);
        gainNode.connect(audioContext.destination);

        oscillator.frequency.value = 800;
        oscillator.type = 'sine';

        gainNode.gain.setValueAtTime(0.3, audioContext.currentTime);
        gainNode.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + 0.5);

        oscillator.start(audioContext.currentTime);
        oscillator.stop(audioContext.currentTime + 0.5);
      } catch (e) {
        console.log('Could not play alert sound:', e);
      }
    },

    // Flash critical indicator
    flashCritical() {
      document.body.style.animation = 'criticalFlash 1s ease-in-out 3';
      setTimeout(() => {
        document.body.style.animation = '';
      }, 3000);
    },

    // Update blocked IP count in sidebar
    updateBlockedIPCount() {
      fetch('/admin/ip_rules/blocked.json')
        .then(res => res.json())
        .then(data => {
          const badge = document.querySelector('[data-blocked-ips-badge]');
          if (badge && data.success) {
            const count = data.data.length;
            if (count > 0) {
              badge.textContent = count;
              badge.style.display = 'inline';
            } else {
              badge.style.display = 'none';
            }
          }
        })
        .catch(err => console.error('Failed to update blocked IP count:', err));
    },

    // Helper: Get badge class for health status
    healthBadgeClass(status) {
      const classes = {
        'healthy': 'badge-success',
        'warning': 'badge-warning',
        'critical': 'badge-error'
      };
      return classes[status] || 'badge-ghost';
    },

    // Helper: Get class for error rate
    errorRateClass(rate) {
      if (rate > 5) return 'text-3xl font-bold text-red-600';
      if (rate > 1) return 'text-3xl font-bold text-yellow-600';
      return 'text-3xl font-bold text-green-600';
    }
  });

  // Request health update every 30 seconds
  setInterval(() => {
    adminMetricsSubscription.perform('request_health_update');
  }, 30000);
});
