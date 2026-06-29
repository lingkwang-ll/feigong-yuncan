import { Router } from 'express';
import {
  adminDeliveryLocationController,
  deliveryLocationController,
} from '../controllers/delivery-location.controller';
import { requireAuth } from '../middleware/auth.middleware';
import { requireBackofficeAccess } from '../middleware/rbac.middleware';

const router = Router();

router.post('/update', requireAuth, deliveryLocationController.update);
router.get('/current', requireAuth, deliveryLocationController.getCurrent);

export const adminDeliveryLocationRouter = Router();
adminDeliveryLocationRouter.get(
  '/current',
  requireAuth,
  requireBackofficeAccess,
  adminDeliveryLocationController.getCurrent,
);

export default router;
