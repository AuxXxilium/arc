const { h, render } = preact;
const { useState, useEffect } = preactHooks;

const SESSION_KEY = 'arc_session_token';
const USERNAME_KEY = 'arc_username';

const APPS = [
  { id: 'terminal', title: 'Terminal', desc: 'SSH terminal access', icon: '🖥️' },
  { id: 'files', title: 'File Manager', desc: 'Browse and manage files', icon: '📂' },
  { id: 'sysinfo', title: 'System Info', desc: 'Hardware and software details', icon: '🩺' }
];

const LINKS = [
  { title: 'Documentation', desc: 'Guides and reference', icon: '📚', url: 'https://xpenology.tech/documentation' },
  { title: 'Arc Management', desc: 'Manage your Arc systems', icon: '🛠️', url: 'https://arc.xpenology.tech' }
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

const CLOSE_ICON = h('svg', { fill: 'none', stroke: 'currentColor', viewBox: '0 0 24 24' },
  h('path', { 'stroke-linecap': 'round', 'stroke-linejoin': 'round', 'stroke-width': '2', d: 'M6 18L18 6M6 6l12 12' })
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

  const navItem = (key, icon, label, desc, active, onClick) =>
    h('button', { key, type: 'button', className: `nav-item${active ? ' active' : ''}`, title: desc, onClick },
      h('span', { className: 'nav-step' }, icon),
      label
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
          navItem('dsm', '🌐', 'Go to DSM', 'Open Xpenology DSM', false,
            () => window.open(`http://${serverIp}:5000`, '_blank')),
          h('div', { className: 'sidebar-header' }, 'External'),
          LINKS.map((link) =>
            navItem(link.url, link.icon, link.title, link.desc, false, () => window.open(link.url, '_blank'))
          )
        ),
        h('main', { className: 'content-area' },
          h('section', { className: 'panel' },
            h('div', { className: 'panel-head' },
              h('span', { className: 'panel-icon' }, current.icon),
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
      h('div', { className: 'login-overlay' },
        h('div', { className: 'login-card' },
          h('img', { className: 'login-mark', src: 'arc_loader.png', alt: 'arc_logo' }),
          h('div', { className: 'login-title' }, 'Arc Web Config'),
          h('div', { className: 'login-subtitle' }, 'Sign in to continue.'),
          loginError && h('div', { className: 'message-box message-error' }, loginError),
          h('form', { onSubmit: handleLogin },
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
            h(
              'button',
              {
                className: 'primary-button button-full',
                type: 'submit',
                disabled: loginSaving
              },
              loginSaving ? 'Signing in...' : 'Sign in'
            )
          )
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
            darkMode ? '☀' : '☾'
          ),
          h('details', { className: 'power-menu' },
            h('summary', { className: 'theme-toggle', title: 'Restart or shut down' }, '⏻'),
            h('div', { className: 'power-menu-items' },
              h('button', {
                className: 'power-item',
                type: 'button',
                onClick: (event) => {
                  closeMenu(event.target);
                  setPowerAction('reboot');
                }
              }, 'Restart'),
              h('button', {
                className: 'power-item danger',
                type: 'button',
                onClick: (event) => {
                  closeMenu(event.target);
                  setPowerAction('poweroff');
                }
              }, 'Shut down')
            )
          ),
          h('details', { className: 'account-menu' },
            h('summary', { className: 'account-button', title: `Signed in as ${username || 'root'}` },
              h('span', { className: 'account-avatar' }, (username || 'root').charAt(0).toUpperCase()),
              h('span', { className: 'account-name' }, username || 'root'),
              h('span', { className: 'account-caret' }, '▾')
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
              }, 'Change password'),
              h('button', {
                className: 'account-item danger',
                type: 'button',
                onClick: (event) => {
                  closeMenu(event.target);
                  handleLogout();
                }
              }, 'Sign out')
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
