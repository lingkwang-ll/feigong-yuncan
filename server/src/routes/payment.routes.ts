import { Router } from 'express';
import { paymentController } from '../controllers/payment.controller';
import { requireAuth } from '../middleware/auth.middleware';

const router = Router();

router.get('/config', paymentController.config);
router.post('/create', requireAuth, paymentController.create);
router.post('/mock-paid', requireAuth, paymentController.mockPaid);
router.post('/wechat/notify', paymentController.wechatNotify);
router.post('/alipay/notify', paymentController.alipayNotify);

export default router;
