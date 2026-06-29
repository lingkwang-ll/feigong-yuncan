import { Router } from 'express';

import {

  adminController,

  companyPublicController,

  merchantOnboardingController,

} from '../controllers/admin.controller';

import { requireAuth } from '../middleware/auth.middleware';

import {

  requireAdminAccess,

  requireBackofficeAccess,

} from '../middleware/rbac.middleware';

import { supportAdminController } from '../controllers/support-admin.controller';
import { couponAdminController } from '../controllers/coupon.controller';
import { merchantAgreementAdminController } from '../controllers/merchant-agreement.controller';

const router = Router();

const auth = [requireAuth, requireBackofficeAccess] as const;

const adminOnly = [requireAuth, requireAdminAccess] as const;



router.post('/companies/register', companyPublicController.register);

router.post('/merchant-onboarding/register', merchantOnboardingController.register);



router.post('/auth/login', adminController.login);

router.post('/auth/password-login', adminController.passwordLogin);

router.get('/auth/me', ...auth, adminController.me);



router.get('/dashboard', ...auth, adminController.dashboard);



router.get('/companies', ...auth, adminController.listCompanies);

router.post('/companies', ...adminOnly, adminController.createCompany);

router.put('/companies', ...adminOnly, adminController.updateCompany);



router.get('/users', ...auth, adminController.listUsers);

router.put('/users/status', ...auth, adminController.setUserStatus);

router.post('/users/:id/reset-password', ...auth, adminController.resetUserPassword);



router.get('/employees', ...auth, adminController.listEmployees);

router.get('/employees/export', ...auth, adminController.exportEmployees);

router.post('/employees', ...auth, adminController.createEmployee);

router.post('/employees/import', ...auth, adminController.importEmployees);

router.put('/employees/:id', ...auth, adminController.updateEmployeeById);

router.put('/employees/:id/enabled', ...auth, adminController.setEmployeeEnabled);

router.put('/employees', ...auth, adminController.updateEmployee);



router.get('/merchants', ...auth, adminController.listMerchants);

router.post('/merchants', ...auth, adminController.createMerchant);

router.put('/merchants/:id', ...auth, adminController.updateMerchantById);

router.put('/merchants/:id/review', ...auth, adminController.reviewMerchantById);

router.put('/merchants/:id/enabled', ...auth, adminController.setMerchantEnabledById);

router.put('/merchants/:id/open', ...auth, adminController.setMerchantOpenById);

router.put('/merchants/:id/payment-qr', ...auth, adminController.updateMerchantPaymentQrById);



router.get('/merchant-onboarding/:id', ...auth, adminController.getMerchantOnboardingDetail);

router.get('/merchant-onboarding', ...auth, adminController.listMerchants);

router.post('/merchant-onboarding/review', ...auth, adminController.reviewMerchant);

router.put('/merchant-onboarding/enabled', ...auth, adminController.setMerchantEnabled);

router.put('/merchant-onboarding/payment-qr', ...auth, adminController.updateMerchantPaymentQr);

router.put('/merchant-onboarding/open', ...auth, adminController.setMerchantOpen);



router.get('/dishes/category-missing', ...auth, adminController.listCategoryMissingDishes);

router.patch('/dishes/category-batch', ...auth, adminController.patchDishCategoryBatch);

router.patch('/dishes/:dishId/category', ...auth, adminController.patchDishCategory);

router.get('/dishes', ...auth, adminController.listDishes);

router.post('/dishes', ...auth, adminController.createDish);

router.put('/dishes/:id', ...auth, adminController.updateDishById);

router.put('/dishes/:id/available', ...auth, adminController.setDishAvailable);

router.put('/dishes/:id/sold-out', ...auth, adminController.setDishSoldOut);

router.put('/dishes/:id/sort', ...auth, adminController.setDishSort);

router.put('/dishes', ...auth, adminController.updateDish);



router.get('/meal-summary', ...auth, adminController.mealSummary);

router.get('/meal-summary/export', ...auth, adminController.exportMealSummary);

router.put('/meal-summary/status', ...auth, adminController.confirmMealSummary);



router.get('/orders', ...auth, adminController.listOrders);

router.get('/labels', ...auth, adminController.listLabels);

router.get('/labels/export-html', ...auth, adminController.exportLabelsHtml);



router.get('/system-config', ...auth, adminController.getSystemConfig);

router.put('/system-config', ...adminOnly, adminController.updateSystemConfig);



router.get('/overtime-rosters', ...auth, adminController.listOvertimeRosters);

router.post('/overtime-rosters', ...auth, adminController.createOvertimeRoster);

router.put('/overtime-rosters/:id/enabled', ...auth, adminController.setOvertimeRosterEnabled);

router.delete('/overtime-rosters/:id', ...auth, adminController.deleteOvertimeRoster);

router.post('/overtime-rosters/import', ...auth, adminController.importOvertimeRosters);

router.get('/settlements', ...auth, adminController.listSettlements);
router.post('/settlements/check', ...auth, adminController.runSettlementCheck);
router.post('/settlements/settle', ...adminOnly, adminController.settleOrder);
router.post('/settlements/force-eligible', ...auth, adminController.forceSettlementEligible);

router.get('/merchants/:merchantId/hygiene', ...auth, adminController.getMerchantHygieneDetail);

router.get('/support/conversations', ...adminOnly, supportAdminController.listConversations);
router.get('/support/unread-count', ...adminOnly, supportAdminController.unreadCount);
router.get(
  '/support/conversations/:id/messages',
  ...adminOnly,
  supportAdminController.listMessages,
);
router.post(
  '/support/conversations/:id/messages',
  ...adminOnly,
  supportAdminController.sendMessage,
);
router.post(
  '/support/conversations/:id/read',
  ...adminOnly,
  supportAdminController.markRead,
);
router.patch(
  '/support/conversations/:id/status',
  ...adminOnly,
  supportAdminController.updateStatus,
);

router.get('/coupons', ...adminOnly, couponAdminController.list);
router.patch('/coupons/:id/status', ...adminOnly, couponAdminController.setStatus);

router.get(
  '/merchant-agreements',
  ...adminOnly,
  merchantAgreementAdminController.list,
);
router.get(
  '/merchant-agreements/export',
  ...adminOnly,
  merchantAgreementAdminController.exportCsv,
);

export default router;

