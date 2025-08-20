// vite.config.js
import { defineConfig } from 'vite';
import { resolve } from 'node:path';

export default defineConfig({
  root: 'src',          // project’s HTML lives in ./src
  base: '/',
  appType: 'mpa',       // dev server = true multi-page

  build: {
    outDir: '../dist',
    assetsDir: 'assets',
    emptyOutDir: true,
    assetsInlineLimit: 0,

    rollupOptions: {
      input: {
        main: resolve(__dirname, 'src/index.html'),
        privacy: resolve(__dirname, 'src/privacy-policy.html'),
        deleteAccount: resolve(__dirname, 'src/delete-account.html'),
        deleteAccountAuth: resolve(__dirname, 'src/delete-account-auth.html'),
        agentJobConfirmed: resolve(__dirname, 'src/agent-job-confirmed.html'),
        agentJobUnavailable: resolve(__dirname, 'src/agent-job-unavailable.html'),
      },
      output: {
        assetFileNames: 'assets/[name].[hash][extname]'
      }
    }
  }
});
