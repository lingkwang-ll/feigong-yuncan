/**
 * pm2 配置 —— 非攻云餐后端
 *
 * 使用：
 *   cd /opt/feigong-yuncan/server
 *   pm2 start ecosystem.config.js
 *   pm2 save
 *   pm2 startup           # 跟随系统自启
 *
 * 常用命令：
 *   pm2 status
 *   pm2 logs feigong-yuncan-server
 *   pm2 restart feigong-yuncan-server
 *   pm2 stop feigong-yuncan-server
 *   pm2 delete feigong-yuncan-server
 *
 * 注意：
 *   - 启动前请先 `npm install && npm run build`
 *   - 日志统一落到 /opt/feigong-yuncan/logs/
 *   - 实际 PORT / DATABASE_PATH / UPLOAD_DIR 等在 .env 中配置
 */
module.exports = {
  apps: [
    {
      name: 'feigong-yuncan-server',
      script: 'dist/index.js',
      cwd: __dirname,
      instances: 1,
      exec_mode: 'fork', // SQLite 不适合多实例，强制单进程
      autorestart: true,
      watch: false,
      max_memory_restart: '300M',
      env: {
        NODE_ENV: 'production',
      },
      // 日志写到 /opt/feigong-yuncan/logs/，方便统一收集
      out_file: '/opt/feigong-yuncan/logs/server.out.log',
      error_file: '/opt/feigong-yuncan/logs/server.err.log',
      merge_logs: true,
      time: true,
    },
  ],
};
