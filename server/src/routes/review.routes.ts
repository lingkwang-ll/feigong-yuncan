import { Router } from 'express';
import { reviewController } from '../controllers/review.controller';
import { requireAuth } from '../middleware/auth.middleware';

const reviewRouter = Router();

reviewRouter.post('/', requireAuth, reviewController.create);
reviewRouter.get('/order/:orderId', requireAuth, reviewController.getByOrder);
reviewRouter.get('/merchant/:merchantId', requireAuth, reviewController.listByMerchant);

export default reviewRouter;
