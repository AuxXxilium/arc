const { h, render } = preact;
const { useState, useEffect } = preactHooks;

const SESSION_KEY = 'arc_session_token';
const USERNAME_KEY = 'arc_username';

// `icon` names a glyph in GLYPHS below.
const APPS = [
  { id: 'terminal', title: 'Terminal', desc: 'SSH terminal access', icon: 'terminal' },
  { id: 'files', title: 'File Manager', desc: 'Browse and manage files', icon: 'folder' },
  { id: 'sysinfo', title: 'System Info', desc: 'Hardware and software details', icon: 'info' }
];

const LINKS = [
  { title: 'Documentation', desc: 'Guides and reference', icon: 'book', url: 'https://xpenology.tech/documentation' },
  { title: 'Arc Management', desc: 'Manage your Arc systems', icon: 'cog', url: 'https://arc.xpenology.tech' }
];

const DEFAULT_CONFIG = { DUFS_PORT: '7304', TTYD_PORT: '7681' };

const buildQuery = (params) =>
  Object.keys(params)
    .map((key) => `${encodeURIComponent(key)}=${encodeURIComponent(params[key])}`)
    .join('&');

const fetchJson = (url, options = {}) =>
  fetch(url, options).then((response) => {
    if (!response.ok) {
      throw new Error(`${response.status} ${response.statusText}`);
    }
    return response.json();
  });

const fetchText = (url, options = {}) =>
  fetch(url, options).then((response) => {
    if (!response.ok) {
      throw new Error(`${response.status} ${response.statusText}`);
    }
    return response.text();
  });

const parseConfig = (text) => {
  const parsed = { ...DEFAULT_CONFIG };
  text.split('\n').forEach((line) => {
    const [key, value] = line.split('=');
    if (key && value) {
      parsed[key.trim()] = value.trim();
    }
  });
  return parsed;
};

const DARK_MODE_KEY = 'arc_dark_mode';

// The file manager is dufs on its own port, so it cannot read this page's
// localStorage. A cookie is shared across ports, so the choice is left
// there for it to read on every page it loads; the message repaints the one
// already open when the switch is flipped.
const THEME_COOKIE = 'arc_theme';

const CLOSE_ICON = h('svg', { fill: 'none', stroke: 'currentColor', viewBox: '0 0 24 24' },
  h('path', { 'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'stroke-width': '2', d: 'M6 18L18 6M6 6l12 12' })
);

// Line icons, after Ignis's: one 24x24 grid and a shared stroke, coloured by
// currentColor. They replace the emoji the sidebar and page headings
// carried, which brought their own palette and rendered differently on
// every platform. Each entry is a list of path data.
const GLYPHS = {
  terminal: ['M4 17l6-5-6-5', 'M12 19h8'],
  folder: ['M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7z'],
  info: ['M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18z', 'M12 11v5', 'M12 8h.01'],
  globe: ['M12 3a9 9 0 1 0 0 18a9 9 0 1 0 0-18z', 'M3 12h18', 'M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18'],
  book: ['M2 4h6a4 4 0 0 1 4 4v13a3 3 0 0 0-3-3H2z', 'M22 4h-6a4 4 0 0 0-4 4v13a3 3 0 0 1 3-3h7z'],
  cog: ['M12 9a3 3 0 1 0 0 6a3 3 0 1 0 0-6z', 'M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z'],
  power: ['M12 3v9', 'M6.6 6.6a9 9 0 1 0 10.8 0'],
  restart: ['M21 12a9 9 0 1 1-3-6.7', 'M21 3v6h-6'],
  key: ['M15.5 3a5.5 5.5 0 1 0 0 11a5.5 5.5 0 1 0 0-11z', 'M11.5 12.5L3 21', 'M6 18l2 2', 'M8.5 15.5l2 2'],
  logout: ['M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4', 'M16 17l5-5-5-5', 'M21 12H9'],
  chevron: ['M6 9l6 6 6-6']
};

const glyph = (name, small) =>
  h('svg', { className: small ? 'icon icon-sm' : 'icon', viewBox: '0 0 24 24', 'aria-hidden': 'true' },
    (GLYPHS[name] || []).map((d) => h('path', { d }))
  );

// The theme switch's sun and moon, solid as in Ignis's header.
const SUN_ICON = h('svg', { className: 'icon icon-solid', viewBox: '0 0 20 20', 'aria-hidden': 'true' },
  h('path', { 'fill-rule': 'evenodd', 'clip-rule': 'evenodd', d: 'M10 2a1 1 0 011 1v1a1 1 0 11-2 0V3a1 1 0 011-1zm4 8a4 4 0 11-8 0 4 4 0 018 0zm-.464 4.95l.707.707a1 1 0 001.414-1.414l-.707-.707a1 1 0 00-1.414 1.414zm2.12-10.607a1 1 0 010 1.414l-.706.707a1 1 0 11-1.414-1.414l.707-.707a1 1 0 011.414 0zM17 11a1 1 0 100-2h-1a1 1 0 100 2h1zm-7 4a1 1 0 011 1v1a1 1 0 11-2 0v-1a1 1 0 011-1zM5.05 6.464A1 1 0 106.465 5.05l-.708-.707a1 1 0 00-1.414 1.414l.707.707zm1.414 8.486l-.707.707a1 1 0 01-1.414-1.414l.707-.707a1 1 0 011.414 1.414zM4 11a1 1 0 100-2H3a1 1 0 000 2h1z' })
);

const MOON_ICON = h('svg', { className: 'icon icon-solid', viewBox: '0 0 20 20', 'aria-hidden': 'true' },
  h('path', { d: 'M17.293 13.293A8 8 0 016.707 2.707a8.001 8.001 0 1010.586 10.586z' })
);

// arx's dialog: a header with the title and a close button, the content,
// and a footer, each divided by a rule. A click on the backdrop closes it.
// With onSubmit the body and footer are one form, so Enter submits.
function modal({ title, onClose, onSubmit, body, footer }) {
  return h('div', {
    className: 'modal-backdrop',
    onClick: (event) => { if (event.target === event.currentTarget) onClose(); }
  },
    h('div', { className: 'modal modal-sm', role: 'dialog', 'aria-modal': 'true' },
      h('div', { className: 'modal-head' },
        h('h2', { className: 'modal-title' }, title),
        h('button', { type: 'button', className: 'modal-close', title: 'Close', onClick: onClose }, CLOSE_ICON)
      ),
      h(onSubmit ? 'form' : 'div', onSubmit ? { onSubmit } : null,
        h('div', { className: 'modal-body' }, body),
        footer && h('div', { className: 'modal-foot' }, footer)
      )
    )
  );
}

function App() {
  const [authenticated, setAuthenticated] = useState(false);
  const [username, setUsername] = useState('');
  const [token, setToken] = useState('');
  const [serverIp, setServerIp] = useState('Loading...');
  const [config, setConfig] = useState(DEFAULT_CONFIG);
  const [activeApp, setActiveApp] = useState('terminal');
  const [loginError, setLoginError] = useState('');
  const [loginSaving, setLoginSaving] = useState(false);
  const [passwordOpen, setPasswordOpen] = useState(false);
  const [passwordError, setPasswordError] = useState('');
  const [passwordSuccess, setPasswordSuccess] = useState('');
  const [passwordSaving, setPasswordSaving] = useState(false);
  // 'reboot' or 'poweroff' while its confirmation is open.
  const [powerAction, setPowerAction] = useState(null);
  const [systemInfo, setSystemInfo] = useState('Loading system information...');
  const [darkMode, setDarkMode] = useState(() => localStorage.getItem(DARK_MODE_KEY) === 'true');

  // The header menus are <details>: they close on a second click and on
  // Escape by themselves, but not on a click somewhere else on the page.
  useEffect(() => {
    const closeMenus = (event) => {
      document.querySelectorAll('.topbar details[open]').forEach((menu) => {
        if (!menu.contains(event.target)) menu.open = false;
      });
    };
    document.addEventListener('click', closeMenus);
    return () => document.removeEventListener('click', closeMenus);
  }, []);

  useEffect(() => {
    if (!passwordOpen && !powerAction) return undefined;
    const onKey = (event) => {
      if (event.key === 'Escape') {
        closePassword();
        setPowerAction(null);
      }
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [passwordOpen, powerAction]);

  useEffect(() => {
    if (darkMode) {
      document.documentElement.classList.add('dark');
    } else {
      document.documentElement.classList.remove('dark');
    }
    localStorage.setItem(DARK_MODE_KEY, darkMode);
    const theme = darkMode ? 'dark' : 'light';
    document.cookie = `${THEME_COOKIE}=${theme}; path=/; max-age=31536000; SameSite=Lax`;
    document.querySelectorAll('.embed-container iframe').forEach((frame) => {
      try {
        if (frame.contentWindow) frame.contentWindow.postMessage({ arcTheme: theme }, '*');
      } catch (error) { /* not loaded yet: it reads the cookie when it is */ }
    });
  }, [darkMode]);

  useEffect(() => {
    const storedToken = localStorage.getItem(SESSION_KEY);
    const storedUsername = localStorage.getItem(USERNAME_KEY);

    loadServerIp();

    if (storedToken && storedUsername) {
      verifySession(storedToken, storedUsername)
        .then((valid) => {
          if (valid) {
            setUsername(storedUsername);
            setToken(storedToken);
            return startServices()
              .then(loadConfig)
              .then(() => setAuthenticated(true))
              .catch(() => setAuthenticated(false));
          }
          setAuthenticated(false);
        })
        .catch(() => setAuthenticated(false));
    }
  }, []);

  useEffect(() => {
    if (authenticated && activeApp === 'sysinfo') {
      fetchSystemInfo();
    }
  }, [authenticated, activeApp]);

  function verifySession(sessionToken, currentUsername) {
    const body = buildQuery({ action: 'verify', token: sessionToken, username: currentUsername });
    return fetchJson('./auth.cgi', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body
    })
      .then((data) => !!data.success)
      .catch(() => false);
  }

  function loadServerIp() {
    fetchText('./get-ip.cgi')
      .then((ip) => setServerIp(ip.trim()))
      .catch(() => setServerIp('Unavailable'));
  }

  function loadConfig() {
    return fetchText('./get-config.cgi')
      .then((text) => {
        const parsed = parseConfig(text);
        setConfig(parsed);
        return parsed;
      })
      .catch(() => DEFAULT_CONFIG);
  }

  function startServices() {
    return fetch('./start-services.cgi', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' }
    })
      .then((response) => {
        if (!response.ok) {
          throw new Error(`${response.status} ${response.statusText}`);
        }
        return response.text();
      })
      .then((text) => {
        const data = JSON.parse(text);
        if (!data.success) {
          throw new Error('Failed to start services');
        }
        const nextConfig = { ...config };
        if (data.ttyd && data.ttyd.port) nextConfig.TTYD_PORT = data.ttyd.port;
        if (data.dufs && data.dufs.port) nextConfig.DUFS_PORT = data.dufs.port;
        setConfig(nextConfig);
        return nextConfig;
      });
  }

  function stopServices() {
    fetch('./stop-services.cgi', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' }
    }).catch(() => {});
  }

  function handleLogin(event) {
    event.preventDefault();
    const formData = new FormData(event.target);
    const user = (formData.get('username') || '').trim();
    const pass = formData.get('password') || '';

    setLoginError('');
    setLoginSaving(true);

    const body = buildQuery({ action: 'login', username: user, password: pass });
    fetch('./auth.cgi', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body
    })
      .then((response) => response.json())
      .then((data) => {
        if (data.success) {
          localStorage.setItem(SESSION_KEY, data.token);
          localStorage.setItem(USERNAME_KEY, user);
          setUsername(user);
          setToken(data.token);
          return startServices().then(loadConfig).then(() => setAuthenticated(true));
        }
        throw new Error(data.message || 'Invalid username or password');
      })
      .catch((error) => {
        setLoginError(error.message || 'Connection error. Please try again.');
      })
      .finally(() => setLoginSaving(false));
  }

  function handlePower() {
    const action = powerAction;
    setPowerAction(null);
    fetch('./shutdown.cgi', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: buildQuery({ action })
    }).catch(() => {});
  }

  function closePassword() {
    setPasswordOpen(false);
    setPasswordError('');
    setPasswordSuccess('');
  }

  // Close the <details> a menu item lives in, so the menu does not stay
  // open behind whatever the item opened.
  function closeMenu(el) {
    const menu = el.closest('details');
    if (menu) menu.open = false;
  }

  function handleLogout() {
    stopServices();
    if (token && username) {
      const body = buildQuery({ action: 'logout', token, username });
      fetch('./auth.cgi', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body
      }).catch(() => {});
    }
    localStorage.removeItem(SESSION_KEY);
    localStorage.removeItem(USERNAME_KEY);
    setAuthenticated(false);
    setToken('');
    setUsername('');
    setActiveApp('terminal');
    setSystemInfo('Loading system information...');
  }

  function handlePasswordSubmit(event) {
    event.preventDefault();
    const formData = new FormData(event.target);
    const newPassword = formData.get('newPassword') || '';
    const confirmPassword = formData.get('confirmPassword') || '';

    if (newPassword !== confirmPassword) {
      setPasswordError('Passwords do not match');
      setPasswordSuccess('');
      return;
    }

    if (newPassword.length < 4) {
      setPasswordError('Password must be at least 4 characters');
      setPasswordSuccess('');
      return;
    }

    setPasswordError('');
    setPasswordSuccess('');
    setPasswordSaving(true);

    fetchText(`./change-password.cgi?${buildQuery({ username, newPassword })}`)
      .then((text) => {
        const data = JSON.parse(text);
        if (!data.success) {
          throw new Error(data.message || 'Failed to change password');
        }
        setPasswordSuccess('Password changed successfully!');
        setPasswordError('');
        event.target.reset();
        setTimeout(() => setPasswordOpen(false), 1800);
      })
      .catch((error) => {
        setPasswordError(error.message || 'Connection error. Please try again.');
      })
      .finally(() => setPasswordSaving(false));
  }

  function fetchSystemInfo() {
    fetchText('./get-sysinfo.cgi')
      .then((data) => setSystemInfo(data))
      .catch(() => setSystemInfo('Error loading system information'));
  }

  function getIframeUrl(appId) {
    if (!serverIp || serverIp === 'Loading...' || serverIp === 'Unavailable') {
      return '';
    }
    const port = appId === 'terminal' ? config.TTYD_PORT : config.DUFS_PORT;
    return `http://${serverIp}:${port}`;
  }

  // An external entry opens somewhere else rather than selecting a page,
  // so it never takes the active treatment and says so with an arrow.
  const navItem = (key, icon, label, desc, active, onClick, external) =>
    h('button', { key, type: 'button', className: `nav-item${active ? ' active' : ''}`, title: desc, onClick },
      h('span', { className: 'nav-step' }, glyph(icon)),
      h('span', { className: 'nav-label' }, label),
      external && h('span', { className: 'nav-external', 'aria-hidden': 'true' }, '↗')
    );

  const current = APPS.find((app) => app.id === activeApp) || APPS[0];

  const activeContent = authenticated
    ? h('div', { className: 'main-layout' },
        h('nav', { className: 'sidebar' },
          h('div', { className: 'sidebar-header' }, 'Navigation'),
          APPS.map((app) =>
            navItem(app.id, app.icon, app.title, app.desc, activeApp === app.id, () => setActiveApp(app.id))
          ),
          h('div', { className: 'sidebar-header' }, 'DSM'),
          navItem('dsm', 'globe', 'Go to DSM', 'Open Xpenology DSM', false,
            () => window.open(`http://${serverIp}:5000`, '_blank'), true),
          h('div', { className: 'sidebar-header' }, 'External'),
          LINKS.map((link) =>
            navItem(link.url, link.icon, link.title, link.desc, false, () => window.open(link.url, '_blank'), true)
          )
        ),
        h('main', { className: 'content-area' },
          h('section', { className: 'panel' },
            h('div', { className: 'panel-head' },
              h('span', { className: 'panel-icon' }, glyph(current.icon)),
              h('div', null,
                h('div', { className: 'panel-title' }, current.title),
                h('div', { className: 'panel-desc' }, current.desc)
              )
            ),
            h('div', { className: 'panel-body' },
              h('div', {
                className: 'embed-container',
                style: { display: activeApp === 'terminal' ? 'block' : 'none' }
              },
                h('iframe', {
                  key: `terminal-${config.TTYD_PORT}-${serverIp}`,
                  src: getIframeUrl('terminal'),
                  title: 'Terminal',
                  allowFullScreen: true
                })
              ),
              h('div', {
                className: 'embed-container',
                style: { display: activeApp === 'files' ? 'block' : 'none' }
              },
                h('iframe', {
                  key: `files-${config.DUFS_PORT}-${serverIp}`,
                  src: getIframeUrl('files'),
                  title: 'File Manager',
                  allowFullScreen: true
                })
              ),
              h('div', {
                className: 'sysinfo-view',
                style: { display: activeApp === 'sysinfo' ? 'block' : 'none' }
              },
                h('div', { className: 'sysinfo-content' }, systemInfo)
              )
            )
          )
        )
      )
    : null;

  return h('div', { className: 'app-shell' },
    !authenticated &&
      // Ignis's sign-in layout: the mark and name above the card, as the
      // header carries them once signed in, with the theme switch beside
      // them; the card holds only the form; one line of help below it.
      h('div', { className: 'login-overlay' },
        h('div', { className: 'login-panel' },
          h('div', { className: 'login-head' },
            h('div', { className: 'topbar-logo' },
              h('img', { className: 'topbar-mark', src: 'arc_loader.png?v=1', alt: 'arc_logo' }),
              h('div', { className: 'topbar-label' },
                h('div', { className: 'topbar-title' }, 'Arc Web Config'),
                h('div', { className: 'topbar-subtitle' }, 'Remote system access and tools')
              )
            ),
            h(
              'button',
              {
                className: 'theme-toggle theme-icon',
                type: 'button',
                onClick: () => setDarkMode(!darkMode),
                title: darkMode ? 'Switch to light mode' : 'Switch to dark mode'
              },
              darkMode ? SUN_ICON : MOON_ICON
            )
          ),
          h('form', { className: 'login-card', onSubmit: handleLogin },
            h('div', { className: 'field-group' },
              h('label', { className: 'field-label', htmlFor: 'username' }, 'Username'),
              h('input', {
                className: 'field-input',
                id: 'username',
                name: 'username',
                type: 'text',
                autoComplete: 'username',
                required: true
              })
            ),
            h('div', { className: 'field-group' },
              h('label', { className: 'field-label', htmlFor: 'password' }, 'Password'),
              h('input', {
                className: 'field-input',
                id: 'password',
                name: 'password',
                type: 'password',
                autoComplete: 'current-password',
                required: true
              })
            ),
            loginError && h('div', { className: 'message-box message-error' }, loginError),
            h(
              'button',
              {
                className: 'primary-button button-full',
                type: 'submit',
                disabled: loginSaving
              },
              loginSaving ? 'Signing in...' : 'Sign in'
            )
          ),
          h('div', { className: 'login-hint' }, 'Sign in to continue.')
        )
      ),
    authenticated &&
      h('header', { className: 'topbar' },
        h('div', { className: 'topbar-logo' },
          h('img', { className: 'topbar-mark', src: 'arc_loader.png?v=1', alt: 'arc_logo' }),
          h('div', { className: 'topbar-label' },
            h('div', { className: 'topbar-title' }, 'Arc Web Config'),
            h('div', { className: 'topbar-subtitle' }, 'Remote system access and tools')
          )
        ),
        h('div', { className: 'topbar-actions' },
          h('div', { className: 'topbar-info', title: 'Address of this computer' }, serverIp),
          h(
            'button',
            {
              className: 'theme-toggle theme-icon',
              type: 'button',
              onClick: () => setDarkMode(!darkMode),
              title: darkMode ? 'Switch to light mode' : 'Switch to dark mode'
            },
            darkMode ? SUN_ICON : MOON_ICON
          ),
          h('details', { className: 'power-menu' },
            h('summary', { className: 'theme-toggle', title: 'Restart or shut down' }, glyph('power')),
            h('div', { className: 'power-menu-items' },
              h('button', {
                className: 'power-item',
                type: 'button',
                onClick: (event) => {
                  closeMenu(event.target);
                  setPowerAction('reboot');
                }
              }, glyph('restart', true), 'Restart'),
              h('button', {
                className: 'power-item danger',
                type: 'button',
                onClick: (event) => {
                  closeMenu(event.target);
                  setPowerAction('poweroff');
                }
              }, glyph('power', true), 'Shut down')
            )
          ),
          h('details', { className: 'account-menu' },
            h('summary', { className: 'account-button', title: `Signed in as ${username || 'root'}` },
              h('span', { className: 'account-avatar' }, (username || 'root').charAt(0).toUpperCase()),
              h('span', { className: 'account-name' }, username || 'root'),
              h('span', { className: 'account-caret' }, glyph('chevron', true))
            ),
            h('div', { className: 'account-items' },
              h('div', { className: 'account-head' },
                h('div', { className: 'account-head-name' }, username || 'root'),
                h('div', { className: 'account-head-note' }, 'This computer’s own account')
              ),
              h('button', {
                className: 'account-item',
                type: 'button',
                onClick: (event) => {
                  closeMenu(event.target);
                  setPasswordOpen(true);
                }
              }, glyph('key', true), 'Change password'),
              h('button', {
                className: 'account-item danger',
                type: 'button',
                onClick: (event) => {
                  closeMenu(event.target);
                  handleLogout();
                }
              }, glyph('logout', true), 'Sign out')
            )
          )
        )
      ),
    authenticated ? activeContent : null,
    passwordOpen &&
      authenticated &&
      modal({
        title: 'Change password',
        onClose: closePassword,
        onSubmit: handlePasswordSubmit,
        body: [
          passwordError && h('div', { className: 'message-box message-error' }, passwordError),
          passwordSuccess && h('div', { className: 'message-box message-success' }, passwordSuccess),
          h('div', { className: 'field-group' },
            h('label', { className: 'field-label', htmlFor: 'newPassword' }, 'New password'),
            h('input', {
              className: 'field-input',
              id: 'newPassword',
              name: 'newPassword',
              type: 'password',
              autoComplete: 'new-password',
              required: true,
              minLength: 4
            })
          ),
          h('div', { className: 'field-group' },
            h('label', { className: 'field-label', htmlFor: 'confirmPassword' }, 'Confirm new password'),
            h('input', {
              className: 'field-input',
              id: 'confirmPassword',
              name: 'confirmPassword',
              type: 'password',
              autoComplete: 'new-password',
              required: true,
              minLength: 4
            })
          )
        ],
        footer: [
          h('button', { type: 'button', className: 'secondary-button', onClick: closePassword }, 'Cancel'),
          h(
            'button',
            { className: 'primary-button', type: 'submit', disabled: passwordSaving },
            passwordSaving ? 'Changing...' : 'Change password'
          )
        ]
      }),
    powerAction &&
      modal({
        title: powerAction === 'reboot' ? 'Restart this computer?' : 'Shut this computer down?',
        onClose: () => setPowerAction(null),
        body: h('p', null,
          powerAction === 'reboot'
            ? 'The page stops responding while it restarts. Open it again once the computer is back up.'
            : 'It switches off completely. To use it again, turn it on with its power button.'
        ),
        footer: [
          h('button', { type: 'button', className: 'secondary-button', onClick: () => setPowerAction(null) }, 'Cancel'),
          h(
            'button',
            { type: 'button', className: powerAction === 'reboot' ? 'primary-button' : 'danger-button', onClick: handlePower },
            powerAction === 'reboot' ? 'Restart' : 'Shut down'
          )
        ]
      })
  );
}

render(h(App), document.getElementById('app'));
