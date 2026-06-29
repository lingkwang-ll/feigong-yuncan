import { Router } from 'express';
import { requireAuth } from '../middleware/auth.middleware';
import { couponController } from '../controllers/coupon.controller';

const router = Router();

router.get('/merchant/:merchantId', requireAuth, couponController.listForMerchantPublic);
router.post('/:id/claim', requireAuth, couponController.claim);
router.get('/my', requireAuth, couponController.listMy);
router.get('/best', requireAuth, couponController.findBest);

export default router;
