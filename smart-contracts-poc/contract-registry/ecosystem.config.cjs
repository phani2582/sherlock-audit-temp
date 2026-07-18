module.exports = {
  apps: [{
    name: 'contract-registry',
    script: 'server.mjs',
    cwd: __dirname,
    env: {
      REGISTRY_PORT: 3030,
      NODE_ENV: 'production',
    },
    instances: 1,
    autorestart: true,
    max_restarts: 10,
    restart_delay: 3000,
  }],
};
