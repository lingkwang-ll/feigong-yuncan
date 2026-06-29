import { Router } from 'express';
import { merchantOnboardingPublicController } from '../controllers/merchant-onboarding.controller';
import { loadUser } from '../middleware/auth.middleware';

const router = Router();

router.use(loadUser);

router.post('/apply', merchantOnboardingPublicController.apply);
router.get('/status', merchantOnboardingPublicController.status);
router.put('/:id/resubmit', merchantOnboardingPublicController.resubmit);

export default router;
