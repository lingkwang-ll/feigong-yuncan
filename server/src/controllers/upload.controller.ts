import fs from 'fs';
import { Request, Response, NextFunction } from 'express';
import {
  BadRequest,
  Forbidden,
  NotFound,
  Unauthorized,
} from '../middleware/error.middleware';
import { conversationMessageToDto, userToDto } from '../models/mappers';
import { authService } from '../services/auth.service';
import { supportConversationService } from '../services/support-conversation.service';
import { supportMessageToDto } from '../models/mappers';
import { conversationService } from '../services/conversation.service';
import { merchantService } from '../services/merchant.service';
import { orderService } from '../services/order.service';
import { toPublicUrl } from '../services/upload.service';
import {
  assertMerchantAccess,
  resolveAdminScope,
} from '../utils/company-scope.util';
import { UserRow } from '../models/types';
import { isAdminRole } from '../constants/roles';

/** 清理已经写到磁盘但本次请求拒绝接受的文件 */
function safeUnlink(req: Request): void {
  if (req.file?.path) {
    try {
      fs.unlinkSync(req.file.path);
    } catch {
      // ignore
    }
  }
}

/**
 * 解析"本次上传所属商家"并完成鉴权
 *
 * - 商家：仅能上传到自己绑定的商家
 * - 平台 / 企业管理员：可显式指定 merchantId，且必须有权限
 * - 员工：禁止
 */
function resolveMerchantIdForUpload(
  req: Request,
  bodyMerchantId?: string,
): string | undefined {
  if (!req.user) throw Unauthorized();
  const user = req.user;
  const scope = resolveAdminScope(user);
  const requested =
    bodyMerchantId ||
    (req.body?.merchantId as string | undefined) ||
    (req.query.merchantId as string | undefined);

  if (scope.isMerchant) {
    if (!scope.merchantId) throw Forbidden('当前账号未绑定商家');
    if (requested && requested !== scope.merchantId) {
      throw Forbidden('无权操作其它商家');
    }
    return scope.merchantId;
  }

  if (scope.isPlatformAdmin || scope.isCompanyAdmin) {
    if (!requested) return undefined; // 后台仅取 URL、不直接落到某个商家
    try {
      assertMerchantAccess(user, requested);
    } catch (e) {
      if ((e as Error).message === 'FORBIDDEN') throw Forbidden('无权操作该商家');
      throw e;
    }
    return requested;
  }

  throw Forbidden('当前角色无权上传该资源');
}

/**
 * 商家资料相关上传（营业执照、店铺照片、入驻申请素材等）
 *
 * - 商家：必须已登录（resubmit / 自助维护），允许在还没有 merchantId 时上传
 * - 平台 / 企业管理员：允许
 * - 员工：禁止
 */
function assertCanUploadMerchantAsset(user: UserRow): void {
  if (
    user.role === 'merchant' ||
    user.role === 'admin' ||
    user.role === 'company_admin'
  ) {
    return;
  }
  throw Forbidden('当前角色无权上传商家资料');
}

export const uploadController = {
  paymentScreenshot(req: Request, res: Response, next: NextFunction) {
    if (!req.user) {
      safeUnlink(req);
      return next(Unauthorized('登录已失效，请重新登录'));
    }
    if (!req.file) return next(BadRequest('缺少文件 file', 'UPLOAD_FILE_REQUIRED'));

    const orderId =
      (req.body?.orderId as string | undefined)?.trim() ||
      (req.query.orderId as string | undefined)?.trim();

    const manualPayChannel =
      (req.body?.manualPayChannel as string | undefined)?.trim() ||
      (req.query.manualPayChannel as string | undefined)?.trim();
    const normalizedChannel =
      manualPayChannel === 'wechat' || manualPayChannel === 'alipay'
        ? manualPayChannel
        : undefined;

    const scope = resolveAdminScope(req.user);
    const isEmployee = req.user.role === 'employee';

    if (isEmployee && !orderId) {
      safeUnlink(req);
      return next(BadRequest('缺少订单 ID', 'ORDER_ID_REQUIRED'));
    }
    if (isEmployee && !normalizedChannel) {
      safeUnlink(req);
      return next(
        BadRequest('请选择微信或支付宝收款码', 'MANUAL_PAY_CHANNEL_REQUIRED'),
      );
    }

    if (orderId) {
      const order = orderService.getById(orderId);
      if (!order) {
        safeUnlink(req);
        return next(NotFound('订单不存在'));
      }
      const isOwnerEmployee =
        req.user.role === 'employee' && order.user_id === req.user.id;
      const isAdminScope =
        scope.isPlatformAdmin ||
        (scope.isCompanyAdmin && order.company_id === scope.companyId);
      if (!isOwnerEmployee && !isAdminScope) {
        safeUnlink(req);
        return next(Forbidden('仅下单人可上传付款截图'));
      }
      if (scope.isMerchant) {
        safeUnlink(req);
        return next(Forbidden('商家不可替员工上传付款截图'));
      }
    }

    const url = toPublicUrl(req.file.path);
    if (orderId) {
      try {
        orderService.submitPaymentScreenshot(
          orderId,
          url,
          normalizedChannel,
        );
      } catch (e) {
        const msg = (e as Error).message;
        if (msg === 'NOT_FOUND') {
          safeUnlink(req);
          return next(NotFound('订单不存在'));
        } else if (msg === 'COMPANY_PAY_NO_SCREENSHOT') {
          safeUnlink(req);
          return next(BadRequest('企业代付订单无需上传付款截图', 'COMPANY_PAY_NO_SCREENSHOT'));
        } else if (msg === 'PAYMENT_UPLOAD_NOT_ALLOWED') {
          safeUnlink(req);
          return next(BadRequest('当前订单状态不允许上传付款截图', 'PAYMENT_UPLOAD_NOT_ALLOWED'));
        } else if (msg === 'INVALID_STATUS_TRANSITION') {
          safeUnlink(req);
          return next(BadRequest('不允许的状态流转', 'INVALID_STATUS_TRANSITION'));
        } else {
          return next(e);
        }
      }
    }
    res.json({ data: { url } });
  },

  dishImage(req: Request, res: Response) {
    if (!req.user) {
      safeUnlink(req);
      throw Unauthorized();
    }
    // 仅允许商家 / 后台账号上传菜品图片
    if (req.user.role === 'employee') {
      safeUnlink(req);
      throw Forbidden('员工不可上传菜品图片');
    }
    // 校验 merchantId（若传入）属于当前用户
    try {
      resolveMerchantIdForUpload(req);
    } catch (e) {
      safeUnlink(req);
      throw e;
    }
    if (!req.file) throw BadRequest('缺少文件 file');
    const url = toPublicUrl(req.file.path);
    res.json({ data: { url } });
  },

  merchantQrCode(req: Request, res: Response) {
    if (!req.user) {
      safeUnlink(req);
      throw Unauthorized();
    }
    if (!req.file) throw BadRequest('上传失败', 'UPLOAD_FAILED');
    let merchantId: string | undefined;
    try {
      merchantId = resolveMerchantIdForUpload(req);
    } catch (e) {
      safeUnlink(req);
      throw e;
    }
    const url = toPublicUrl(req.file.path);
    if (merchantId) {
      try {
        const channel = (req.body?.channel as string | undefined)?.trim();
        if (channel === 'wechat' || channel === 'alipay') {
          merchantService.updateChannelPaymentQr(merchantId, channel, url);
        } else {
          merchantService.updatePaymentQrCode(merchantId, url);
        }
      } catch {
        // 不影响上传结果
      }
    }
    res.json({ data: { url } });
  },

  merchantLicense(req: Request, res: Response) {
    if (!req.user) {
      safeUnlink(req);
      throw Unauthorized();
    }
    try {
      assertCanUploadMerchantAsset(req.user);
    } catch (e) {
      safeUnlink(req);
      throw e;
    }
    if (!req.file) throw BadRequest('上传失败', 'UPLOAD_FAILED');
    const url = toPublicUrl(req.file.path);
    res.json({ data: { url } });
  },

  storePhoto(req: Request, res: Response) {
    if (!req.user) {
      safeUnlink(req);
      throw Unauthorized();
    }
    try {
      assertCanUploadMerchantAsset(req.user);
    } catch (e) {
      safeUnlink(req);
      throw e;
    }
    if (!req.file) throw BadRequest('上传失败', 'UPLOAD_FAILED');
    const url = toPublicUrl(req.file.path);
    res.json({ data: { url } });
  },

  /**
   * 会话图片消息上传
   *
   * 路由：
   *   POST /api/conversations/:conversationId/images       （员工 / 平台管理员）
   *   POST /api/merchant/conversations/:conversationId/images  （商家 / 平台管理员）
   *
   * 权限校验：解析 conversation -> resolveAccess；若拒绝则删除已落盘的临时文件。
   * 成功后直接写入一条 image 消息并返回完整消息 DTO。
   */
  conversationImage(req: Request, res: Response) {
    if (!req.user) {
      safeUnlink(req);
      throw Unauthorized();
    }
    const conversationId =
      (req.params.conversationId as string | undefined) ||
      (req.body?.conversationId as string | undefined);
    if (!conversationId) {
      safeUnlink(req);
      throw BadRequest('缺少 conversationId');
    }
    const conv = conversationService.getById(conversationId);
    if (!conv) {
      safeUnlink(req);
      throw NotFound('会话不存在');
    }

    let role: 'employee' | 'merchant' | 'admin';
    try {
      role = conversationService.resolveAccess(req.user, conv).role;
    } catch (e) {
      safeUnlink(req);
      if ((e as Error).message === 'FORBIDDEN') {
        throw Forbidden('无权访问该会话');
      }
      throw e;
    }
    if (role === 'admin') {
      safeUnlink(req);
      throw Forbidden('管理员不能直接发送会话消息');
    }

    // 路径前缀强校验：员工接口不能给商家走，反之亦然
    const sidePath = req.baseUrl + req.path;
    const isMerchantPath = sidePath.includes('/merchant/');
    if (isMerchantPath && role !== 'merchant') {
      safeUnlink(req);
      throw Forbidden('请通过员工接口上传');
    }
    if (!isMerchantPath && role !== 'employee') {
      safeUnlink(req);
      throw Forbidden('请通过商家接口上传');
    }

    if (!req.file) {
      throw BadRequest('缺少文件 file', 'UPLOAD_FAILED');
    }
    const url = toPublicUrl(req.file.path);

    try {
      const msg = conversationService.sendMessage({
        conversationId: conv.id,
        user: req.user,
        role,
        messageType: 'image',
        imageUrl: url,
      });
      res.json({ data: conversationMessageToDto(msg) });
    } catch (e) {
      // 写消息失败：删除文件避免污染
      safeUnlink(req);
      throw e;
    }
  },

  merchantLogo(req: Request, res: Response) {
    if (!req.user) {
      safeUnlink(req);
      throw Unauthorized();
    }
    if (!req.file) throw BadRequest('上传失败', 'UPLOAD_FAILED');
    let merchantId: string | undefined;
    try {
      merchantId = resolveMerchantIdForUpload(req);
    } catch (e) {
      safeUnlink(req);
      throw e;
    }
    const url = toPublicUrl(req.file.path);
    if (merchantId) {
      try {
        merchantService.updateLogo(merchantId, url);
      } catch {
        // 不影响上传结果
      }
    }
    res.json({ data: { url } });
  },

  /**
   * 平台客服图片消息
   * POST /api/support/conversation/images
   * POST /api/uploads/support-image（仅上传 URL，需 conversationId）
   */
  supportImage(req: Request, res: Response, next: NextFunction) {
    if (!req.user) {
      safeUnlink(req);
      return next(Unauthorized('登录已过期，请重新登录'));
    }
    if (!req.file) {
      return next(BadRequest('缺少文件 file', 'UPLOAD_FILE_REQUIRED'));
    }
    const url = toPublicUrl(req.file.path);
    const sidePath = req.baseUrl + req.path;
    const isSupportConversationPath = sidePath.includes('/support/conversation');

    if (isSupportConversationPath) {
      if (req.user.role !== 'employee' && req.user.role !== 'merchant') {
        safeUnlink(req);
        return next(Forbidden('仅员工或商家可上传客服图片'));
      }
      try {
        const conv = supportConversationService.getOrCreateForUser(req.user);
        supportConversationService.assertUserAccess(req.user, conv);
        const msg = supportConversationService.sendUserMessage({
          conversationId: conv.id,
          user: req.user,
          messageType: 'image',
          imageUrl: url,
        });
        return res.json({ data: supportMessageToDto(msg) });
      } catch (e) {
        safeUnlink(req);
        if ((e as Error).message === 'FORBIDDEN') {
          return next(Forbidden('无权访问该会话'));
        }
        return next(e);
      }
    }

    // /api/uploads/support-image — 管理员回复时先上传再发消息
    const conversationId =
      (req.body?.conversationId as string | undefined)?.trim() ||
      (req.query.conversationId as string | undefined)?.trim();
    if (!conversationId) {
      return res.json({ data: { url } });
    }
    if (!isAdminRole(req.user.role)) {
      safeUnlink(req);
      return next(Forbidden('需要管理员权限'));
    }
    try {
      const conv = supportConversationService.getById(conversationId);
      if (!conv) {
        safeUnlink(req);
        return next(NotFound('会话不存在'));
      }
      const msg = supportConversationService.sendAdminMessage({
        conversationId: conv.id,
        admin: req.user,
        messageType: 'image',
        imageUrl: url,
      });
      return res.json({ data: supportMessageToDto(msg) });
    } catch (e) {
      safeUnlink(req);
      return next(e);
    }
  },

  /** 员工头像：仅员工本人可上传并写入 users.avatar_url */
  employeeAvatar(req: Request, res: Response, next: NextFunction) {
    if (!req.user) {
      safeUnlink(req);
      return next(Unauthorized('登录已过期，请重新登录'));
    }
    if (req.user.role !== 'employee') {
      safeUnlink(req);
      return next(Forbidden('仅员工可上传头像'));
    }
    if (!req.file) {
      return next(BadRequest('缺少文件 file', 'UPLOAD_FILE_REQUIRED'));
    }
    const url = toPublicUrl(req.file.path);
    try {
      const updated = authService.updateAvatarUrl(req.user.id, url);
      res.json({
        data: {
          url,
          user: userToDto(updated),
        },
      });
    } catch (e) {
      safeUnlink(req);
      if ((e as Error).message === 'USER_NOT_FOUND') {
        return next(NotFound('用户不存在'));
      }
      return next(e);
    }
  },

  /** 员工评价图片上传（需 completed 订单且为下单人） */
  reviewImage(req: Request, res: Response, next: NextFunction) {
    if (!req.user) {
      safeUnlink(req);
      return next(Unauthorized('登录已过期，请重新登录'));
    }
    if (req.user.role !== 'employee') {
      safeUnlink(req);
      return next(Forbidden('仅员工可上传评价图片'));
    }
    if (!req.file) {
      return next(BadRequest('缺少文件 file', 'UPLOAD_FILE_REQUIRED'));
    }

    const orderId =
      (req.body?.orderId as string | undefined)?.trim() ||
      (req.query.orderId as string | undefined)?.trim();
    if (!orderId) {
      safeUnlink(req);
      return next(BadRequest('缺少订单 ID', 'ORDER_ID_REQUIRED'));
    }

    const order = orderService.getById(orderId);
    if (!order) {
      safeUnlink(req);
      return next(NotFound('订单不存在'));
    }
    if (order.user_id !== req.user.id) {
      safeUnlink(req);
      return next(Forbidden('无权评价该订单'));
    }
    if (order.status !== 'completed') {
      safeUnlink(req);
      return next(BadRequest('订单未完成，不能评价', 'ORDER_NOT_COMPLETED'));
    }

    const url = toPublicUrl(req.file.path);
    res.json({ data: { url } });
  },
};
