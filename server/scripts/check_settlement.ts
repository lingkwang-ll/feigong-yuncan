/**
 * 检查到期可结算订单并标记 eligible
 * npm run settlement:check
 */
import 'dotenv/config';
import { closeDb, getDb } from '../src/db/database';
import { settlementService } from '../src/services/settlement.service';

getDb();
const count = settlementService.runEligibilityCheck();
console.log(`[settlement:check] marked eligible: ${count}`);
closeDb();
