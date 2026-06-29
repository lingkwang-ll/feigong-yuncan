import 'dotenv/config';
import { createApp } from './app';
import { paymentConfigService } from './services/payment-config.service';

const PORT = Number(process.env.PORT || 3000);
const HOST = process.env.HOST || '0.0.0.0';

const app = createApp();

paymentConfigService.logStartupChecks();

app.listen(PORT, HOST, () => {
  const publicBase =
    process.env.PUBLIC_BASE_URL || `http://localhost:${PORT}`;
  // eslint-disable-next-line no-console
  console.log('[feigong-yuncan-server] started');
  // eslint-disable-next-line no-console
  console.log(`  - bind         : ${HOST}:${PORT}`);
  // eslint-disable-next-line no-console
  console.log(`  - api base     : ${publicBase}/api`);
  // eslint-disable-next-line no-console
  console.log(`  - upload dir   : ${process.env.UPLOAD_DIR || './uploads'}`);
  // eslint-disable-next-line no-console
  console.log(
    `  - database     : ${
      process.env.DATABASE_PATH ||
      process.env.DATABASE_FILE ||
      './data/feigong-yuncan.db'
    }`,
  );
  // eslint-disable-next-line no-console
  console.log(`  - cors origin  : ${process.env.CORS_ORIGIN || '*'}`);
});
