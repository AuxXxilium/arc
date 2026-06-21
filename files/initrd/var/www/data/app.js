const { h, render } = preact;
const { useState, useEffect } = preactHooks;

const SESSION_KEY = 'arc_session_token';
const USERNAME_KEY = 'arc_username';

const APPS = [
  { id: 'terminal', title: 'Terminal', desc: 'SSH terminal access', icon: '🖥️' },
  { id: 'files', title: 'File Manager', desc: 'Browse and manage files', icon: '📂' },
  { id: 'sysinfo', title: 'System Info', desc: 'Hardware and software details', icon: '🩺' }
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
  const [shutdownOpen, setShutdownOpen] = useState(false);
  const [systemInfo, setSystemInfo] = useState('Loading system information...');
  const [darkMode, setDarkMode] = useState(() => localStorage.getItem(DARK_MODE_KEY) === 'true');

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

  function handleShutdown() {
    setShutdownOpen(false);
    fetch('./shutdown.cgi', { method: 'POST' }).catch(() => {});
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

  const activeContent = authenticated
    ? h('div', { className: 'main-layout' },
        h('div', { className: 'sidebar' },
          h('div', { className: 'sidebar-header' }, 'Navigation'),
          h('div', { className: 'card-grid' },
            APPS.map((app) =>
              h(
                'div',
                {
                  key: app.id,
                  className: `app-card ${activeApp === app.id ? 'active' : ''}`,
                  onClick: () => setActiveApp(app.id)
                },
                h('div', { className: 'app-card-icon' }, app.icon),
                h('div', { className: 'app-card-info' },
                  h('div', { className: 'app-card-title' }, app.title),
                  h('div', { className: 'app-card-desc' }, app.desc)
                )
              )
            )
          ),
          h('div', { className: 'sidebar-header' }, 'External'),
          h('div', { className: 'card-grid' },
            h(
              'div',
              {
                className: 'app-card',
                onClick: () => window.open(`http://${serverIp}:5000`, '_blank')
              },
              h('div', { className: 'app-card-icon' }, '🌐'),
              h('div', { className: 'app-card-info' },
                h('div', { className: 'app-card-title' }, 'Go to DSM'),
                h('div', { className: 'app-card-desc' }, 'Open Xpenology DSM')
              )
            ),
            h(
              'div',
              {
                className: 'app-card',
                onClick: () => window.open('https://xpenology.tech/wiki', '_blank')
              },
              h('div', { className: 'app-card-icon' }, '📚'),
              h('div', { className: 'app-card-info' },
                h('div', { className: 'app-card-title' }, 'Wiki'),
                h('div', { className: 'app-card-desc' }, 'Documentation')
              )
            )
          )
        ),
        h('div', { className: 'content-area' },
          h('div', { className: 'panel' },
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
          h('div', { className: 'login-logo' },
            h('img', { src: 'arc_loader.png', alt: 'arc_logo' })
          ),
          h('div', { className: 'login-title' }, 'Arc Web Config'),
          h('div', { className: 'login-subtitle' }, 'Sign in to continue'),
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
              loginSaving ? 'Signing in...' : 'Sign In'
            )
          )
        )
      ),
    authenticated &&
      h('div', { className: 'topbar' },
        h('div', { className: 'topbar-logo' },
          h('img', { src: 'arc_loader.png?v=1', alt: 'arc_logo' }),
          h('div', { className: 'topbar-label' },
            h('div', { className: 'topbar-title' }, 'Arc Web Config'),
            h('div', { className: 'topbar-subtitle' }, 'Remote system access and tools')
          )
        ),
        h('div', { className: 'topbar-actions' },
          h('span', null, `IP: ${serverIp}`),
          h(
            'button',
            {
              className: 'theme-toggle',
              type: 'button',
              onClick: () => setDarkMode(!darkMode),
              title: darkMode ? 'Switch to light mode' : 'Switch to dark mode'
            },
            darkMode ? '☀️' : '🌙'
          ),
          h(
            'button',
            { className: 'secondary-button', type: 'button', onClick: () => setPasswordOpen(true) },
            'Change Password'
          ),
          h('button', { className: 'secondary-button', type: 'button', onClick: handleLogout }, 'Logout'),
          h('button', { className: 'danger-button', type: 'button', onClick: () => setShutdownOpen(true) }, 'Shutdown')
        )
      ),
    authenticated ? activeContent : null,
    passwordOpen &&
      authenticated &&
      h('div', { className: 'login-overlay' },
        h('div', { className: 'password-card' },
          h('div', { className: 'password-title' }, 'Change Password'),
          passwordError && h('div', { className: 'message-box message-error' }, passwordError),
          passwordSuccess && h('div', { className: 'message-box message-success' }, passwordSuccess),
          h('form', { onSubmit: handlePasswordSubmit },
            h('div', { className: 'field-group' },
              h('label', { className: 'field-label', htmlFor: 'newPassword' }, 'New Password'),
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
              h('label', { className: 'field-label', htmlFor: 'confirmPassword' }, 'Confirm New Password'),
              h('input', {
                className: 'field-input',
                id: 'confirmPassword',
                name: 'confirmPassword',
                type: 'password',
                autoComplete: 'new-password',
                required: true,
                minLength: 4
              })
            ),
            h('div', { className: 'button-row' },
              h(
                'button',
                {
                  type: 'button',
                  className: 'secondary-button',
                  onClick: () => {
                    setPasswordOpen(false);
                    setPasswordError('');
                    setPasswordSuccess('');
                  }
                },
                'Cancel'
              ),
              h(
                'button',
                { className: 'primary-button', type: 'submit', disabled: passwordSaving },
                passwordSaving ? 'Changing...' : 'Change Password'
              )
            )
          )
        )
      ),
    shutdownOpen &&
      h('div', { className: 'login-overlay' },
        h('div', { className: 'password-card' },
          h('div', { className: 'password-title' }, 'Shutdown'),
          h('div', { style: { textAlign: 'center', color: 'var(--muted)', fontSize: '14px', marginBottom: '24px' } },
            'Are you sure you want to shut down the system?'
          ),
          h('div', { className: 'button-row' },
            h('button', { type: 'button', className: 'danger-button', onClick: handleShutdown }, 'Shutdown'),
            h('button', { type: 'button', className: 'secondary-button', onClick: () => setShutdownOpen(false) }, 'Cancel')
          )
        )
      )
  );
}

render(h(App), document.getElementById('app'));
