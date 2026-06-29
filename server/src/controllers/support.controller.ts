import { NextFunction, Request, Response } from 'express';
import {
  BadRequest,
  Forbidden,
  HttpError,
  NotFound,
  Unauthorized,
} from '../middleware/error.middleware';
import {
  supportConversationToDto,
  supportMessageToDto,
} from '../models/mappers';
import {
  SupportConversationRow,
  SupportMessageType,
  UserRow,
} from '../models/types';
import { supportConversationService } from '../services/support-conversation.service';
import { getDb } from '../db/database';

function ensureUser(req: Request): UserRow {
  if (!req.user) throw Unauthorized();
  return req.user;
}

function ensureAppUser(user: UserRow): UserRow {
  if (user.role !== 'employee' && user.role !== 'merchant') {
    throw Forbidden('仅员工或商家可联系平台客服');
  }
  return user;
}

function mapSupportError(e: unknown): never {
  if (e instanceof HttpError) throw e;
  const code = (e as Error).message;
  switch (code) {
    case 'CONVERSATION_NOT_FOUND':
      throw NotFound('会话不存在');
    case 'FORBIDDEN':
      throw Forbidden('无权访问该会话');
    case 'INVALID_USER_ROLE':
      throw Forbidden('当前角色不可联系平台客服');
    case 'CONTENT_REQUIRED':
      throw BadRequest('消息内容不能为空');
    case 'CONTENT_TOO_LONG':
      throw BadRequest('消息内容过长');
    case 'IMAGE_URL_REQUIRED':
      throw BadRequest('缺少图片地址');
    case 'INVALID_MESSAGE_TYPE':
      throw BadRequest('不支持的消息类型');
    default:
      throw e;
  }
}

function forwardSupportError(e: unknown, next: NextFunction): void {
  try {
    mapSupportError(e);
  } catch (err) {
    next(err);
  }
}

function enrichConversation(row: SupportConversationRow) {
  const db = getDb();
  const user = db
    .prepare<[string], { name: string; nickname: string | null; phone: string }>(
      'SELECT name, nickname, phone FROM users WHERE id = ?',
    )
    .get(row.user_id);
  let merchantName: string | null = null;
  if (row.merchant_id) {
    const m = db
      .prepare<[string], { name: string }>(
        'SELECT name FROM merchants WHERE id = ?',
      )
      .get(row.merchant_id);
    merchantName = m?.name ?? null;
  }
  return supportConversationToDto(row, {
    userName: user?.nickname ?? user?.name ?? null,
    userPhone: user?.phone ?? null,
    merchantName,
  });
}

export const supportController = {
  /** GET /api/support/conversation */
  getOrCreateConversation(req: Request, res: Response, next: NextFunction) {
    try {
      const user = ensureAppUser(ensureUser(req));
      const conv = supportConversationService.getOrCreateForUser(user);
      res.json({ data: enrichConversation(conv) });
    } catch (e) {
      forwardSupportError(e, next);
    }
  },

  /** GET /api/support/conversation/messages */
  listMessages(req: Request, res: Response, next: NextFunction) {
    try {
      const user = ensureAppUser(ensureUser(req));
      const conv = supportConversationService.getOrCreateForUser(user);
      supportConversationService.assertUserAccess(user, conv);
      const rows = supportConversationService.messages(conv.id);
      res.json({ data: rows.map(supportMessageToDto) });
    } catch (e) {
      forwardSupportError(e, next);
    }
  },

  /** POST /api/support/conversation/messages */
  sendMessage(req: Request, res: Response, next: NextFunction) {
    try {
      const user = ensureAppUser(ensureUser(req));
      const conv = supportConversationService.getOrCreateForUser(user);
      const body = req.body ?? {};
      const messageType = (body.messageType as SupportMessageType) || 'text';
      const msg = supportConversationService.sendUserMessage({
        conversationId: conv.id,
        user,
        messageType,
        content: body.content,
        imageUrl: body.imageUrl,
      });
      res.json({ data: supportMessageToDto(msg) });
    } catch (e) {
      forwardSupportError(e, next);
    }
  },

  /** POST /api/support/conversation/read */
  markRead(req: Request, res: Response, next: NextFunction) {
    try {
      const user = ensureAppUser(ensureUser(req));
      const conv = supportConversationService.getOrCreateForUser(user);
      const updated = supportConversationService.markUserRead(conv.id, user);
      res.json({ data: enrichConversation(updated) });
    } catch (e) {
      forwardSupportError(e, next);
    }
  },

  /** GET /api/support/unread-count */
  unreadCount(req: Request, res: Response, next: NextFunction) {
    try {
      const user = ensureAppUser(ensureUser(req));
      const role = user.role as 'employee' | 'merchant';
      const count = supportConversationService.userUnreadTotal(user.id, role);
      res.json({ data: { count } });
    } catch (e) {
      forwardSupportError(e, next);
    }
  },
};
