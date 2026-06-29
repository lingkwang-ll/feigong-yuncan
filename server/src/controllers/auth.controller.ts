import { Request, Response } from 'express';
import {
  BadRequest,
  NotFound,
  TooManyRequests,
  Unauthorized,
} from '../middleware/error.middleware';
import { userToDtoWithProfileStatus } from '../models/mappers';
import { UserRole } from '../models/types';
import { authService } from '../services/auth.service';
import { employeeProfileService } from '../services/employee-profile.service';
import { passwordAuthService } from '../services/password-auth.service';
import { smsAuthService } from '../services/sms-auth.service';
import { normalizePhone } from '../utils/phone.util';

const VALID_ROLES: UserRole[] = ['employee', 'merchant'];

function mapPasswordError(err: unknown): never {
  const code = (err as Error).message;
  switch (code) {
    case 'INVALID_PHONE':
      throw BadRequest('手机号格式不正确');
    case 'PASSWORD_MISMATCH':
      throw BadRequest('密码错误');
    case 'PASSWORD_TOO_SHORT':
      throw BadRequest('新密码至少 6 位');
    case 'EMPLOYEE_NOT_REGISTERED':
      throw BadRequest('该手机号未开通员工账号，请联系管理员');
    case 'EMPLOYEE_DISABLED':
      throw BadRequest('该员工账号已停用，请联系管理员');
    case 'EMPLOYEE_ORDER_FORBIDDEN':
      throw BadRequest('该员工暂未开通订餐权限，请联系管理员');
    case 'EMPLOYEE_ROLE_MISMATCH':
      throw BadRequest('该账号不是员工账号，请选择正确身份');
    case 'USER_DISABLED':
    case 'ACCOUNT_DISABLED':
      throw BadRequest('账号已被禁用');
    case 'MERCHANT_NOT_FOUND':
      throw BadRequest('该手机号暂无商家账号，请先申请入驻');
    case 'MERCHANT_PENDING':
      throw BadRequest('入驻申请审核中，请等待管理员审核');
    case 'MERCHANT_REJECTED': {
      const reason =
        (err as Error & { rejectReason?: string }).rejectReason?.trim() ||
        '未说明原因';
      throw BadRequest(`入驻申请未通过：${reason}`);
    }
    case 'MERCHANT_DISABLED':
      throw BadRequest('商家账号已停用，请联系管理员');
    case 'NOT_FOUND':
      throw NotFound('用户不存在');
    default:
      if (code === 'JWT_SECRET 未配置') {
        throw BadRequest('服务端 JWT 未配置');
      }
      throw err;
  }
}

function mapSmsError(err: unknown): never {
  const code = (err as Error).message;
  switch (code) {
    case 'INVALID_PHONE':
      throw BadRequest('手机号格式不正确');
    case 'INVALID_SCENE':
      throw BadRequest('scene 非法');
    case 'SEND_TOO_FREQUENT':
      throw TooManyRequests('发送过于频繁，请 60 秒后再试');
    case 'DAILY_LIMIT_EXCEEDED':
      throw TooManyRequests('今日验证码发送次数已达上限');
    case 'INVALID_CODE':
      throw BadRequest('验证码格式不正确');
    case 'CODE_NOT_FOUND':
      throw BadRequest('请先获取验证码');
    case 'CODE_MISMATCH':
      throw BadRequest('验证码错误');
    case 'CODE_EXPIRED':
      throw BadRequest('验证码已过期，请重新获取');
    case 'USER_DISABLED':
      throw BadRequest('账号已被禁用');
    case 'EMPLOYEE_NOT_REGISTERED':
      throw BadRequest('该手机号未开通员工账号，请联系管理员');
    case 'EMPLOYEE_DISABLED':
      throw BadRequest('该员工账号已停用，请联系管理员');
    case 'EMPLOYEE_ORDER_FORBIDDEN':
      throw BadRequest('该员工暂未开通订餐权限，请联系管理员');
    case 'EMPLOYEE_ROLE_MISMATCH':
      throw BadRequest('该账号不是员工账号，请选择正确身份');
    case 'USER_NOT_FOUND':
      throw BadRequest('该手机号未开通员工账号，请联系管理员');
    case 'INVALID_ROLE':
      throw BadRequest('role 必须是 employee 或 merchant');
    case 'MERCHANT_NOT_FOUND':
      throw BadRequest('该手机号暂无商家账号，请先申请入驻');
    case 'MERCHANT_PENDING':
      throw BadRequest('入驻申请审核中，请等待管理员审核');
    case 'MERCHANT_REJECTED': {
      const reason =
        (err as Error & { rejectReason?: string }).rejectReason?.trim() ||
        '未说明原因';
      throw BadRequest(`入驻申请未通过：${reason}，可重新提交`);
    }
    case 'MERCHANT_DISABLED':
      throw BadRequest('商家账号已停用，请联系管理员');
    case 'ROLE_MISMATCH':
      throw BadRequest('该手机号不是商家账号，请先申请入驻');
    default:
      if (code === 'JWT_SECRET 未配置') {
        throw BadRequest('服务端 JWT 未配置');
      }
      throw err;
  }
}

function mapBindError(err: unknown): never {
  const code = (err as Error).message;
  switch (code) {
    case 'ALREADY_BOUND':
      throw BadRequest('员工身份已绑定，不可重复提交');
    default:
      throw err;
  }
}

export const authController = {
  /** 兼容旧脚本：验证码登录（仍保留） */
  login(req: Request, res: Response) {
    const { phone, code, role } = req.body ?? {};
    if (!phone || typeof phone !== 'string') {
      throw BadRequest('phone 不能为空');
    }
    if (!code || typeof code !== 'string') {
      throw BadRequest('code 不能为空');
    }
    if (!VALID_ROLES.includes(role)) {
      throw BadRequest('role 必须是 employee 或 merchant');
    }
    try {
      const user = authService.login(normalizePhone(phone), code, role);
      const profile = employeeProfileService.getByUserId(user.id);
      res.json({ data: userToDtoWithProfileStatus(user, profile) });
    } catch (e) {
      mapSmsError(e);
    }
  },

  passwordLogin(req: Request, res: Response) {
    const { phone, password, role } = req.body ?? {};
    if (!phone || typeof phone !== 'string') {
      throw BadRequest('phone 不能为空');
    }
    if (!password || typeof password !== 'string') {
      throw BadRequest('password 不能为空');
    }
    if (role !== 'employee' && role !== 'merchant') {
      throw BadRequest('role 必须是 employee 或 merchant');
    }
    try {
      const result = passwordAuthService.loginApp(phone, password, role);
      const profile = employeeProfileService.getByUserId(result.user.id);
      res.json({
        data: {
          token: result.token,
          user: userToDtoWithProfileStatus(result.user, profile),
        },
      });
    } catch (e) {
      mapPasswordError(e);
    }
  },

  changePassword(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const { oldPassword, newPassword } = req.body ?? {};
    if (!oldPassword || typeof oldPassword !== 'string') {
      throw BadRequest('oldPassword 不能为空');
    }
    if (!newPassword || typeof newPassword !== 'string') {
      throw BadRequest('newPassword 不能为空');
    }
    try {
      passwordAuthService.changePassword(req.user.id, oldPassword, newPassword);
      res.json({ data: { ok: true, message: '密码修改成功' } });
    } catch (e) {
      mapPasswordError(e);
    }
  },

  sendSmsCode(req: Request, res: Response) {
    const { phone, scene } = req.body ?? {};
    if (!phone || typeof phone !== 'string') {
      throw BadRequest('phone 不能为空');
    }
    const sceneVal = typeof scene === 'string' && scene ? scene : 'login';
    try {
      smsAuthService.sendCode(
        phone,
        sceneVal,
        req.ip || req.socket.remoteAddress,
      );
      res.json({ data: { ok: true, message: '验证码已发送' } });
    } catch (e) {
      mapSmsError(e);
    }
  },

  smsLogin(req: Request, res: Response) {
    const { phone, code, role } = req.body ?? {};
    if (!phone || typeof phone !== 'string') {
      throw BadRequest('phone 不能为空');
    }
    if (!code || typeof code !== 'string') {
      throw BadRequest('code 不能为空');
    }
    const roleVal =
      role === 'merchant' || role === 'employee' ? role : undefined;
    try {
      const result = smsAuthService.loginWithCode(phone, code, roleVal);
      const profile = employeeProfileService.getByUserId(result.user.id);
      res.json({
        data: {
          token: result.token,
          user: userToDtoWithProfileStatus(result.user, profile),
        },
      });
    } catch (e) {
      mapSmsError(e);
    }
  },

  logout(_req: Request, res: Response) {
    res.json({ data: { ok: true } });
  },

  me(req: Request, res: Response) {
    const userId = (req.query.userId as string | undefined) || req.user?.id;
    if (!userId) throw BadRequest('缺少 userId');
    try {
      const user = authService.getById(userId);
      if (!user) throw NotFound('用户不存在');
      res.json({ data: employeeProfileService.buildAuthMeDto(user) });
    } catch (e) {
      if ((e as Error).message === 'USER_DISABLED') {
        throw Unauthorized('账号已被禁用');
      }
      throw e;
    }
  },

  bindEmployeeProfile(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const { employeeName, employeeNo, departmentId, departmentName } =
      req.body ?? {};
    if (!employeeName || typeof employeeName !== 'string') {
      throw BadRequest('employeeName 不能为空');
    }
    if (!employeeNo || typeof employeeNo !== 'string') {
      throw BadRequest('employeeNo 不能为空');
    }
    if (!departmentId || typeof departmentId !== 'string') {
      throw BadRequest('departmentId 不能为空');
    }
    if (!departmentName || typeof departmentName !== 'string') {
      throw BadRequest('departmentName 不能为空');
    }
    try {
      const result = employeeProfileService.bindProfile(req.user, {
        employeeName,
        employeeNo,
        departmentId,
        departmentName,
      });
      res.json({
        data: {
          employeeProfile: result.profile,
          employeeProfileStatus: result.employeeProfileStatus,
        },
      });
    } catch (e) {
      mapBindError(e);
    }
  },
};
