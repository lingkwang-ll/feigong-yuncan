import { Router } from 'express';
import { merchantController } from '../controllers/merchant.controller';
import { couponController } from '../controllers/coupon.controller';
import { merchantAgreementController } from '../controllers/merchant-agreement.controller';
import { requireAuth } from '../middleware/auth.middleware';

// 注意：附近商家列表挂在 /api/merchants 下，
// 商家自己的资料挂在 /api/merchant 下。
const nearbyRouter = Router();
nearbyRouter.get('/', merchantController.listNearby);

const merchantRouter = Router();
merchantRouter.get('/profile', requireAuth, merchantController.getMyProfile);
merchantRouter.put(
  '/payment-qr-code',
  requireAuth,
  merchantController.updatePaymentQrCode,
);
merchantRouter.put('/is-open', requireAuth, merchantController.updateIsOpen);
merchantRouter.put('/profile', requireAuth, merchantController.updateProfile);
merchantRouter.put(
  '/delivery-settings',
  requireAuth,
  merchantController.updateDeliverySettings,
);
merchantRouter.put(
  '/business-hours',
  requireAuth,
  merchantController.updateBusinessHours,
);
merchantRouter.get('/wallet', requireAuth, merchantController.getWallet);
merchantRouter.get(
  '/wallet/settlements',
  requireAuth,
  merchantController.listSettlementDetails,
);
merchantRouter.get(
  '/withdrawals',
  requireAuth,
  merchantController.listWithdrawals,
);
merchantRouter.post(
  '/withdrawals',
  requireAuth,
  merchantController.createWithdrawal,
);
merchantRouter.get('/hygiene-stats', requireAuth, merchantController.getHygieneStats);
merchantRouter.get('/reviews', requireAuth, merchantController.listReviews);
merchantRouter.get(
  '/meal-labels/print-status',
  requireAuth,
  merchantController.getMealLabelPrintStatus,
);
merchantRouter.post(
  '/meal-labels/mark-printed',
  requireAuth,
  merchantController.markMealLabelsPrinted,
);
merchantRouter.get('/coupons', requireAuth, couponController.listMerchantCoupons);
merchantRouter.post('/coupons', requireAuth, couponController.createMerchantCoupon);
merchantRouter.patch(
  '/coupons/:id/status',
  requireAuth,
  couponController.setMerchantCouponStatus,
);
merchantRouter.post(
  '/agreement/sign',
  requireAuth,
  merchantAgreementController.sign,
);

export { nearbyRouter, merchantRouter };
