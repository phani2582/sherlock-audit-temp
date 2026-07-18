module.exports = {
  apps: [{
    name: 'config-ui',
    script: 'server.mjs',
    cwd: __dirname,
    env: { CONFIG_PORT: '3031', BASE_PATH: '/proxy/3031' },
  }],
};
