import { Router } from 'express';
import { authController } from '../controllers/auth.controller';
import { requireAuth } from '../middleware/auth.middleware';

const router = Router();

router.post('/login', authController.login);
router.post('/password-login', authController.passwordLogin);
router.post('/change-password', requireAuth, authController.changePassword);
router.post('/sms/send', authController.sendSmsCode);
router.post('/sms/login', authController.smsLogin);
router.post('/logout', authController.logout);
router.get('/me', authController.me);
router.post(
  '/employee-profile/bind',
  requireAuth,
  authController.bindEmployeeProfile,
);

export default router;
