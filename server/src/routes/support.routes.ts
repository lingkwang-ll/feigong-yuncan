import { Router } from 'express';
import { requireAuth } from '../middleware/auth.middleware';
import { supportController } from '../controllers/support.controller';
import { uploadController } from '../controllers/upload.controller';
import { buildUploader, singleFileUpload } from './upload.routes';

const supportImageUploader = buildUploader('supports');

const router = Router();

router.get('/conversation', requireAuth, supportController.getOrCreateConversation);
router.get('/conversation/messages', requireAuth, supportController.listMessages);
router.post('/conversation/messages', requireAuth, supportController.sendMessage);
router.post('/conversation/read', requireAuth, supportController.markRead);
router.get('/unread-count', requireAuth, supportController.unreadCount);
router.post(
  '/conversation/images',
  requireAuth,
  singleFileUpload(supportImageUploader, uploadController.supportImage),
);

export default router;
