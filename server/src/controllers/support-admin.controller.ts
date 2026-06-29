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
  SupportConversationStatus,
  SupportMessageType,
  UserRow,
} from '../models/types';
import { supportConversationService } from '../services/support-conversation.service';
import { getDb } from '../db/database';
import { isAdminRole } from '../constants/roles';

function ensureAdmin(req: Request): UserRow {
  if (!req.user) throw Unauthorized();
  if (!isAdminRole(req.user.role)) throw Forbidden('需要管理员权限');
  return req.user;
}

function ensureConversation(id: string): SupportConversationRow {
  const conv = supportConversationService.getById(id);
  if (!conv) throw NotFound('会话不存在');
  return conv;
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

function mapSupportError(e: unknown): never {
  if (e instanceof HttpError) throw e;
  const code = (e as Error).message;
  switch (code) {
    case 'CONVERSATION_NOT_FOUND':
      throw NotFound('会话不存在');
    case 'INVALID_STATUS':
      throw BadRequest('无效的状态');
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

export const supportAdminController = {
  /** GET /api/admin/support/conversations */
  listConversations(_req: Request, res: Response) {
    ensureAdmin(_req);
    const rows = supportConversationService.listForAdmin();
    res.json({ data: rows.map(enrichConversation) });
  },

  /** GET /api/admin/support/unread-count */
  unreadCount(_req: Request, res: Response) {
    ensureAdmin(_req);
    res.json({
      data: { count: supportConversationService.adminUnreadTotal() },
    });
  },

  /** GET /api/admin/support/conversations/:id/messages */
  listMessages(req: Request, res: Response) {
    ensureAdmin(req);
    const conv = ensureConversation(req.params.id);
    const rows = supportConversationService.messages(conv.id);
    res.json({ data: rows.map(supportMessageToDto) });
  },

  /** POST /api/admin/support/conversations/:id/messages */
  sendMessage(req: Request, res: Response, next: NextFunction) {
    const admin = ensureAdmin(req);
    const conv = ensureConversation(req.params.id);
    const body = req.body ?? {};
    const messageType = (body.messageType as SupportMessageType) || 'text';
    try {
      const msg = supportConversationService.sendAdminMessage({
        conversationId: conv.id,
        admin,
        messageType,
        content: body.content,
        imageUrl: body.imageUrl,
      });
      res.json({ data: supportMessageToDto(msg) });
    } catch (e) {
      forwardSupportError(e, next);
    }
  },

  /** POST /api/admin/support/conversations/:id/read */
  markRead(req: Request, res: Response) {
    ensureAdmin(req);
    const conv = ensureConversation(req.params.id);
    const updated = supportConversationService.markAdminRead(conv.id);
    res.json({ data: enrichConversation(updated) });
  },

  /** PATCH /api/admin/support/conversations/:id/status */
  updateStatus(req: Request, res: Response, next: NextFunction) {
    ensureAdmin(req);
    const conv = ensureConversation(req.params.id);
    const status = (req.body?.status as SupportConversationStatus) || '';
    if (!status) throw BadRequest('status 不能为空');
    try {
      const updated = supportConversationService.updateStatus(conv.id, status);
      res.json({ data: enrichConversation(updated) });
    } catch (e) {
      forwardSupportError(e, next);
    }
  },
};
