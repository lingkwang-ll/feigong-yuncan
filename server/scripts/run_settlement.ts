/**
 * 执行结算（将 eligible 结算单标记 settled，需传 settlementId）
 * npm run settlement:run -- --id=MSxxx
 */
import 'dotenv/config';
import { closeDb, getDb } from '../src/db/database';
import { settlementService } from '../src/services/settlement.service';

const idArg = process.argv.find((a) => a.startsWith('--id='));
const settlementId = idArg?.split('=')[1];
if (!settlementId) {
  console.error('Usage: npm run settlement:run -- --id=SETTLEMENT_ID');
  process.exit(1);
}

getDb();
try {
  const row = settlementService.settle(settlementId);
  console.log('[settlement:run] settled', row.settlement_no, row.order_id);
} catch (e) {
  console.error('[settlement:run] failed:', (e as Error).message);
  process.exit(1);
} finally {
  closeDb();
}
