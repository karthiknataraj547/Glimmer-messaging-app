/* Global dashboard enhancements shared by every deployed admin portal copy. */
(function () {
  'use strict';

  function addDashboardHero() {
    const main = document.querySelector('main');
    if (!main || document.getElementById('maximalistHero')) return;

    const hero = document.createElement('section');
    hero.id = 'maximalistHero';
    hero.className = 'maximalist-hero';
    hero.setAttribute('aria-labelledby', 'maximalistHeroTitle');
    hero.innerHTML = `
      <div>
        <span class="maximalist-eyebrow">SYSTEM PULSE / ADMIN ONLY</span>
        <h2 id="maximalistHeroTitle">Big picture, bright signals, precise control.</h2>
        <p>Monitor the relay, protect accounts, and ship updates from one expressive command deck. Every action remains connected to the same live data controls below.</p>
      </div>
      <div class="maximalist-hero-art" aria-hidden="true">✦</div>
    `;
    main.insertBefore(hero, main.firstChild);
  }

  function syncTabAccessibility() {
    const tabs = Array.from(document.querySelectorAll('.tab-btn'));
    tabs.forEach((tab) => {
      const isSelected = tab.classList.contains('active');
      tab.setAttribute('aria-selected', String(isSelected));
      tab.setAttribute('tabindex', isSelected ? '0' : '-1');
    });
    document.querySelectorAll('.tab-pane').forEach((pane) => {
      pane.setAttribute('aria-hidden', String(!pane.classList.contains('active')));
    });
  }

  function enhanceTabs() {
    const tabList = document.querySelector('.tabs-nav');
    if (!tabList) return;
    tabList.setAttribute('role', 'tablist');
    tabList.setAttribute('aria-label', 'Admin dashboard sections');

    const tabs = Array.from(tabList.querySelectorAll('.tab-btn'));
    tabs.forEach((tab, index) => {
      const inlineHandler = tab.getAttribute('onclick') || '';
      const match = inlineHandler.match(/switchTab\('([^']+)'/);
      const panelId = match && match[1];
      tab.id = tab.id || `admin-tab-${index + 1}`;
      tab.setAttribute('role', 'tab');
      if (panelId) {
        tab.setAttribute('aria-controls', panelId);
        const panel = document.getElementById(panelId);
        if (panel) {
          panel.setAttribute('role', 'tabpanel');
          panel.setAttribute('aria-labelledby', tab.id);
        }
      }
      tab.addEventListener('click', () => window.setTimeout(syncTabAccessibility, 0));
    });

    tabList.addEventListener('keydown', (event) => {
      if (!['ArrowRight', 'ArrowLeft', 'Home', 'End'].includes(event.key)) return;
      const currentIndex = Math.max(0, tabs.indexOf(document.activeElement));
      let nextIndex = currentIndex;
      if (event.key === 'ArrowRight') nextIndex = (currentIndex + 1) % tabs.length;
      if (event.key === 'ArrowLeft') nextIndex = (currentIndex - 1 + tabs.length) % tabs.length;
      if (event.key === 'Home') nextIndex = 0;
      if (event.key === 'End') nextIndex = tabs.length - 1;
      event.preventDefault();
      tabs[nextIndex].focus();
      tabs[nextIndex].click();
    });

    syncTabAccessibility();
  }

  function enhanceLogin() {
    const overlay = document.getElementById('authOverlay');
    if (!overlay) return;
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.setAttribute('aria-label', 'Administrator sign in');

    document.addEventListener('keydown', (event) => {
      if (event.key !== 'Enter' || !event.target.closest('#authOverlay')) return;
      if (event.target.matches('button, textarea, select')) return;
      event.preventDefault();
      if (typeof window.handleAdminLogin === 'function') window.handleAdminLogin();
    });
  }

  function enhanceStatus() {
    const toast = document.getElementById('toast');
    if (toast) {
      toast.setAttribute('role', 'status');
      toast.setAttribute('aria-live', 'polite');
    }
    const status = document.getElementById('liveStatusText');
    if (status) status.setAttribute('aria-live', 'polite');
  }

  // The activity filter/button in the legacy markup called this function, but
  // it was never implemented. Keep it small and share the existing request,
  // renderer, error, and re-authentication mechanisms.
  window.fetchActivityLogs = async function fetchActivityLogs() {
    if (typeof adminToken === 'undefined' || !adminToken) return;
    const filter = document.getElementById('logTypeFilter');
    const type = filter ? filter.value : 'all';

    try {
      const response = await adminFetch(
        `/v1/admin/activity?limit=50&type=${encodeURIComponent(type)}`,
        { headers: { Authorization: `Bearer ${adminToken}` } }
      );
      const data = await safeJson(response);

      if (response.status === 401 || response.status === 403) {
        consecutiveAuthErrors += 1;
        if (consecutiveAuthErrors >= 3 && typeof handleAdminLogout === 'function') {
          handleAdminLogout();
        }
        return;
      }

      if (!response.ok || !data.success) {
        throw new Error(data.error || `Unable to load activity (HTTP ${response.status})`);
      }

      consecutiveAuthErrors = 0;
      renderActivity(data.logs || []);
    } catch (error) {
      console.error('Fetch activity error:', error);
      if (typeof showToast === 'function') {
        showToast('Could not refresh the activity feed. Check the server connection.');
      }
    }
  };

  document.addEventListener('DOMContentLoaded', () => {
    addDashboardHero();
    enhanceTabs();
    enhanceLogin();
    enhanceStatus();
  });
})();
