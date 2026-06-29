import { Request, Response } from 'express';
import {
  BadRequest,
  Forbidden,
  NotFound,
  Unauthorized,
} from '../middleware/error.middleware';
import { todayDateStr } from '../constants/meal';
import {
  companyToDto,
  dishToDto,
  merchantOnboardingToDto,
  normalizeDishCategory,
  reviewToDto,
  userToDto,
} from '../models/mappers';
import { ALL_DISH_CATEGORIES, ALL_MEAL_TYPES, DishCategory, MealType, ReviewRow } from '../models/types';
import { ADMIN_ROLES, BACKOFFICE_ROLES } from '../constants/roles';
import { adminService } from '../services/admin.service';
import {
  employeesToCsv,
  labelsToHtml,
  mealSummaryToCsv,
} from '../services/admin-export.service';
import { companyService } from '../services/company.service';
import { dishService } from '../services/dish.service';
import { mealSummaryService } from '../services/meal-summary.service';
import { overtimeRosterService, parseRosterMealType } from '../services/overtime-roster.service';
import { merchantCreditService } from '../services/merchant-credit.service';
import { settlementService } from '../services/settlement.service';
import { reviewService } from '../services/review.service';
import { merchantOnboardingService } from '../services/merchant-onboarding.service';
import { passwordAuthService } from '../services/password-auth.service';
import { smsAuthService } from '../services/sms-auth.service';
import { auditAdminOperation } from '../utils/admin-audit.util';

function parseDishCategoryInput(v: unknown): DishCategory {
  if (typeof v !== 'string' || !v.trim()) throw BadRequest('category 不能为空');
  const norm = normalizeDishCategory(v);
  if (!norm || !ALL_DISH_CATEGORIES.includes(norm)) {
    throw BadRequest(
      'category 非法，合法值：meat / vegetable / extra / staple / soup / drink',
    );
  }
  return norm;
}

function mapSmsError(err: unknown): never {
  const code = (err as Error).message;
  if (code === 'CODE_MISMATCH') throw BadRequest('验证码错误');
  if (code === 'CODE_EXPIRED') throw BadRequest('验证码已过期');
  if (code === 'CODE_NOT_FOUND') throw BadRequest('请先获取验证码');
  if (code === 'USER_DISABLED') throw BadRequest('账号已被禁用');
  throw err;
}

function mapAdminPasswordError(err: unknown): never {
  const code = (err as Error).message;
  if (code === 'INVALID_PHONE') throw BadRequest('手机号格式不正确');
  if (code === 'PASSWORD_MISMATCH') throw BadRequest('密码错误');
  if (code === 'ACCOUNT_NOT_FOUND') throw BadRequest('账号不存在');
  if (code === 'NO_BACKOFFICE_ACCESS') throw BadRequest('当前账号无后台权限');
  if (code === 'ACCOUNT_DISABLED') throw BadRequest('账号已停用');
  if (code === 'PASSWORD_TOO_SHORT') throw BadRequest('新密码至少 6 位');
  if (code === 'NOT_FOUND') throw NotFound('用户不存在');
  if (code === 'FORBIDDEN') throw Unauthorized('无权操作');
  throw err;
}

export const adminController = {
  /** 管理后台短信登录（保留兼容） */
  login(req: Request, res: Response) {
    const { phone, code } = req.body ?? {};
    if (!phone || !code) throw BadRequest('phone 与 code 不能为空');
    try {
      const { user } = smsAuthService.loginWithCode(phone, code);
      if (!BACKOFFICE_ROLES.includes(user.role)) {
        throw Unauthorized('非管理后台账号');
      }
      res.json({ data: adminService.adminLoginUser(user) });
    } catch (e) {
      mapSmsError(e);
    }
  },

  /** 管理后台账号密码登录 */
  passwordLogin(req: Request, res: Response) {
    const { phone, password } = req.body ?? {};
    if (!phone || !password) throw BadRequest('phone 与 password 不能为空');
    try {
      const { user } = passwordAuthService.loginBackoffice(phone, password);
      res.json({ data: adminService.adminLoginUser(user) });
    } catch (e) {
      mapAdminPasswordError(e);
    }
  },

  resetUserPassword(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    try {
      adminService.resetUserPassword(req.user, req.params.id);
      auditAdminOperation(req, 'reset.user_password', {
        targetId: req.params.id,
      });
      res.json({ data: { ok: true, message: '密码已重置为 123456' } });
    } catch (e) {
      mapAdminPasswordError(e);
    }
  },

  me(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    res.json({ data: userToDto(req.user) });
  },

  listCompanies(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const list = companyService.listForUser(req.user).map((c) => {
      const enriched = companyService.getWithContact(c.id);
      return {
        ...companyToDto(c),
        contactName: enriched?.contactName ?? '—',
        contactPhone: enriched?.contactPhone ?? '—',
      };
    });
    res.json({ data: list });
  },

  updateCompany(req: Request, res: Response) {
    if (!req.user || req.user.role !== 'admin') {
      throw Unauthorized('仅平台管理员可编辑企业');
    }
    const { id, companyName, status } = req.body ?? {};
    if (!id) throw BadRequest('id 不能为空');
    const row = companyService.update(id, { companyName, status });
    res.json({ data: companyToDto(row) });
  },

  createCompany(req: Request, res: Response) {
    if (!req.user || req.user.role !== 'admin') {
      throw Unauthorized('仅平台管理员可创建企业');
    }
    const { companyName, adminPhone, adminName } = req.body ?? {};
    if (!companyName || !adminPhone) {
      throw BadRequest('companyName 与 adminPhone 不能为空');
    }
    const result = companyService.create({ companyName, adminPhone, adminName });
    res.json({
      data: {
        company: result.company,
        adminUser: userToDto(result.adminUser),
      },
    });
  },

  listUsers(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const role = req.query.role as string | undefined;
    const list = adminService.listUsers(req.user, role).map((u) => userToDto(u));
    res.json({ data: list });
  },

  setUserStatus(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const { userId, status } = req.body ?? {};
    if (!userId || !['active', 'disabled'].includes(status)) {
      throw BadRequest('参数非法');
    }
    try {
      const user = adminService.setUserStatus(req.user, userId, status);
      auditAdminOperation(req, 'user.set_status', {
        targetType: 'user',
        targetId: userId,
        detail: { status },
      });
      res.json({ data: userToDto(user) });
    } catch (e) {
      const msg = (e as Error).message;
      if (msg === 'NOT_FOUND') throw NotFound('用户不存在');
      if (msg === 'FORBIDDEN') throw Unauthorized('无权操作');
      throw e;
    }
  },

  listEmployees(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    try {
      res.json({ data: adminService.listEmployees(req.user) });
    } catch (e) {
      if ((e as Error).message === 'FORBIDDEN') throw Forbidden('无权访问员工列表');
      throw e;
    }
  },

  createEmployee(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const { name, phone, departmentName, employeeNo, role, companyId, canOrder, status } =
      req.body ?? {};
    if (!name || !phone) throw BadRequest('姓名与手机号不能为空');
    try {
      const row = adminService.createEmployee(req.user, {
        name,
        phone,
        departmentName: departmentName?.trim() || '未分配',
        employeeNo,
        role,
        companyId,
        canOrder: canOrder !== false,
        status: status === 'disabled' ? 'disabled' : 'active',
      });
      res.json({ data: row });
    } catch (e) {
      const code = (e as Error).message;
      if (code === 'INVALID_PHONE') throw BadRequest('手机号格式不正确');
      if (code === 'PHONE_EXISTS') throw BadRequest('手机号已存在');
      if (code === 'FORBIDDEN') throw Forbidden('无权创建员工');
      throw e;
    }
  },

  updateEmployee(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const { userId, name, phone, departmentName, employeeNo, role, status, canOrder } =
      req.body ?? {};
    if (!userId) throw BadRequest('userId 不能为空');
    try {
      const row = adminService.updateEmployee(req.user, userId, {
        name,
        phone,
        departmentName,
        employeeNo,
        role,
        status,
        canOrder: canOrder === undefined ? undefined : !!canOrder,
      });
      res.json({ data: row });
    } catch (e) {
      const code = (e as Error).message;
      if (code === 'NOT_FOUND') throw NotFound('员工不存在');
      if (code === 'FORBIDDEN') throw Unauthorized('无权操作');
      if (code === 'INVALID_PHONE') throw BadRequest('手机号格式不正确');
      if (code === 'PHONE_EXISTS') throw BadRequest('手机号已存在');
      throw e;
    }
  },

  importEmployees(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const { rows } = req.body ?? {};
    if (!Array.isArray(rows)) throw BadRequest('rows 必须为数组');
    try {
      const result = adminService.importEmployees(req.user, rows);
      res.json({ data: result });
    } catch (e) {
      if ((e as Error).message === 'FORBIDDEN') throw Unauthorized('无权操作');
      throw e;
    }
  },

  exportEmployees(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    try {
      const rows = adminService.listEmployees(req.user);
      const csv = employeesToCsv(rows);
      auditAdminOperation(req, 'export.employees', {
        detail: { count: rows.length },
      });
      res.setHeader('Content-Type', 'text/csv; charset=utf-8');
      res.setHeader('Content-Disposition', 'attachment; filename=employees.csv');
      res.send('\ufeff' + csv);
    } catch (e) {
      if ((e as Error).message === 'FORBIDDEN') throw Unauthorized('无权操作');
      throw e;
    }
  },

  updateEmployeeById(req: Request, res: Response) {
    req.body = { ...req.body, userId: req.params.id };
    return adminController.updateEmployee(req, res);
  },

  setEmployeeEnabled(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const enabled = req.body?.enabled;
    if (typeof enabled !== 'boolean') throw BadRequest('enabled 必填');
    try {
      const row = adminService.updateEmployee(req.user, req.params.id, {
        status: enabled ? 'active' : 'disabled',
      });
      res.json({ data: row });
    } catch (e) {
      if ((e as Error).message === 'NOT_FOUND') throw NotFound('员工不存在');
      if ((e as Error).message === 'FORBIDDEN') throw Unauthorized('无权操作');
      throw e;
    }
  },

  listMerchants(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const status = req.query.status as 'pending' | 'approved' | 'rejected' | undefined;
    const list = merchantOnboardingService.listAdminDtos(req.user, status);
    res.json({ data: list });
  },

  createMerchant(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const { merchantName, address, phone, companyId, paymentQr, menuInit, autoApprove } =
      req.body ?? {};
    if (!merchantName || !address || !phone || !companyId) {
      throw BadRequest('merchantName / address / phone / companyId 不能为空');
    }
    try {
      const dto = merchantOnboardingService.createByAdmin(req.user, {
        merchantName,
        address,
        phone,
        companyId,
        paymentQr,
        menuInit: !!menuInit,
        autoApprove: autoApprove !== false,
      });
      res.json({ data: dto });
    } catch (e) {
      if ((e as Error).message === 'FORBIDDEN') throw Unauthorized('无权操作');
      throw e;
    }
  },

  updateMerchantById(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const { merchantName, address, phone, companyId } = req.body ?? {};
    try {
      const dto = merchantOnboardingService.updateByAdmin(req.user, req.params.id, {
        merchantName,
        address,
        phone,
        companyId,
      });
      res.json({ data: dto });
    } catch (e) {
      if ((e as Error).message === 'NOT_FOUND') throw NotFound('商家不存在');
      if ((e as Error).message === 'FORBIDDEN') throw Unauthorized('无权操作');
      throw e;
    }
  },

  reviewMerchantById(req: Request, res: Response) {
    req.body = {
      ...req.body,
      merchantId: req.params.id,
      status: req.body?.status,
      rejectReason: req.body?.rejectReason,
    };
    return adminController.reviewMerchant(req, res);
  },

  setMerchantEnabledById(req: Request, res: Response) {
    req.body = { merchantId: req.params.id, enabled: req.body?.enabled };
    return adminController.setMerchantEnabled(req, res);
  },

  setMerchantOpenById(req: Request, res: Response) {
    req.body = { merchantId: req.params.id, isOpen: req.body?.isOpen };
    return adminController.setMerchantOpen(req, res);
  },

  updateMerchantPaymentQrById(req: Request, res: Response) {
    req.body = { merchantId: req.params.id, paymentQr: req.body?.paymentQr };
    return adminController.updateMerchantPaymentQr(req, res);
  },

  listMerchantOnboarding(req: Request, res: Response) {
    return adminController.listMerchants(req, res);
  },

  reviewMerchant(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const { merchantId, status, rejectReason } = req.body ?? {};
    if (!merchantId || !['approved', 'rejected'].includes(status)) {
      throw BadRequest('参数非法');
    }
    try {
      const m = merchantOnboardingService.review(
        merchantId,
        status,
        req.user,
        rejectReason,
      );
      auditAdminOperation(req, 'merchant.review', {
        targetType: 'merchant',
        targetId: merchantId,
        detail: { status, rejectReason },
      });
      res.json({ data: merchantOnboardingService.toAdminDto(m) });
    } catch (e) {
      if ((e as Error).message === 'NOT_FOUND') throw NotFound('商家不存在');
      if ((e as Error).message === 'FORBIDDEN') throw Unauthorized('无权审核');
      if ((e as Error).message === 'REJECT_REASON_REQUIRED') {
        throw BadRequest('驳回时必须填写原因');
      }
      throw e;
    }
  },

  getMerchantOnboardingDetail(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    try {
      const data = merchantOnboardingService.getDetail(req.params.id, req.user);
      res.json({ data });
    } catch (e) {
      if ((e as Error).message === 'NOT_FOUND') throw NotFound('商家不存在');
      if ((e as Error).message === 'FORBIDDEN') throw Unauthorized('无权查看');
      throw e;
    }
  },

  setMerchantEnabled(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const { merchantId, enabled } = req.body ?? {};
    if (!merchantId || typeof enabled !== 'boolean') {
      throw BadRequest('参数非法');
    }
    try {
      const m = merchantOnboardingService.setEnabled(merchantId, enabled, req.user);
      res.json({ data: merchantOnboardingService.toAdminDto(m) });
    } catch (e) {
      if ((e as Error).message === 'NOT_FOUND') throw NotFound('商家不存在');
      if ((e as Error).message === 'FORBIDDEN') throw Unauthorized('无权操作');
      throw e;
    }
  },

  updateMerchantPaymentQr(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const { merchantId, paymentQr } = req.body ?? {};
    if (!merchantId || !paymentQr) throw BadRequest('参数非法');
    try {
      const m = merchantOnboardingService.updatePaymentQr(
        merchantId,
        paymentQr,
        req.user,
      );
      res.json({ data: merchantOnboardingService.toAdminDto(m) });
    } catch (e) {
      if ((e as Error).message === 'NOT_FOUND') throw NotFound('商家不存在');
      if ((e as Error).message === 'FORBIDDEN') throw Unauthorized('无权操作');
      throw e;
    }
  },

  setMerchantOpen(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const { merchantId, isOpen } = req.body ?? {};
    if (!merchantId || typeof isOpen !== 'boolean') {
      throw BadRequest('参数非法');
    }
    try {
      const m = merchantOnboardingService.updateOpen(merchantId, isOpen, req.user);
      res.json({ data: merchantOnboardingService.toAdminDto(m) });
    } catch (e) {
      if ((e as Error).message === 'NOT_FOUND') throw NotFound('商家不存在');
      if ((e as Error).message === 'FORBIDDEN') throw Unauthorized('无权操作');
      throw e;
    }
  },

  listDishes(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const merchantId = req.query.merchantId as string | undefined;
    const mealType = req.query.mealType as MealType | undefined;
    if (mealType && !ALL_MEAL_TYPES.includes(mealType)) {
      throw BadRequest('mealType 非法');
    }
    res.json({
      data: adminService.dishDtos(req.user, merchantId, mealType),
    });
  },

  listCategoryMissingDishes(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    if (!BACKOFFICE_ROLES.includes(req.user.role)) {
      throw Forbidden('员工无权操作菜品分类');
    }
    const merchantId = req.query.merchantId as string | undefined;
    res.json({
      data: adminService.listCategoryMissingDishes(req.user, merchantId),
    });
  },

  patchDishCategory(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    if (!BACKOFFICE_ROLES.includes(req.user.role)) {
      throw Forbidden('员工无权操作菜品分类');
    }
    const dishId = req.params.dishId || req.params.id;
    if (!dishId) throw BadRequest('缺少 dishId');
    const category = parseDishCategoryInput(req.body?.category);
    try {
      const row = adminService.updateDishCategoryOnly(req.user, dishId, category);
      auditAdminOperation(req, 'dish.category.update', {
        targetType: 'dish',
        targetId: dishId,
        detail: { category },
      });
      res.json({ data: dishToDto(row) });
    } catch (e) {
      const msg = (e as Error).message;
      if (msg === 'NOT_FOUND') throw NotFound('菜品不存在');
      if (msg === 'FORBIDDEN') throw Forbidden('无权操作该菜品');
      if (msg === 'INVALID_CATEGORY') throw BadRequest('category 非法');
      if (msg === 'EXTRA_PRICE_REQUIRED')
        throw BadRequest('加菜分类必须填写加菜价格，请先在菜品编辑页设置 extraPrice');
      if (msg === 'INVALID_EXTRA_PRICE') throw BadRequest('extraPrice 非法');
      throw e;
    }
  },

  patchDishCategoryBatch(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    if (!BACKOFFICE_ROLES.includes(req.user.role)) {
      throw Forbidden('员工无权操作菜品分类');
    }
    const items = req.body?.items;
    if (!Array.isArray(items) || items.length === 0) {
      throw BadRequest('items 不能为空');
    }
    if (items.length > 200) {
      throw BadRequest('单次最多更新 200 条');
    }
    const parsed: Array<{ dishId: string; category: DishCategory }> = [];
    for (const raw of items) {
      if (!raw || typeof raw.dishId !== 'string' || !raw.dishId.trim()) {
        throw BadRequest('items 中 dishId 非法');
      }
      parsed.push({
        dishId: raw.dishId.trim(),
        category: parseDishCategoryInput(raw.category),
      });
    }
    try {
      const rows = adminService.batchUpdateDishCategories(req.user, parsed);
      auditAdminOperation(req, 'dish.category.batch_update', {
        targetType: 'dish',
        targetId: parsed.map((p) => p.dishId).join(','),
        detail: { count: parsed.length, items: parsed },
      });
      res.json({ data: rows.map(dishToDto) });
    } catch (e) {
      const msg = (e as Error).message;
      if (msg === 'NOT_FOUND') throw NotFound('菜品不存在');
      if (msg === 'FORBIDDEN') throw Forbidden('无权操作部分菜品');
      if (msg === 'EXTRA_PRICE_REQUIRED')
        throw BadRequest('加菜分类必须填写加菜价格，请先在菜品编辑页设置 extraPrice');
      if (msg === 'INVALID_EXTRA_PRICE') throw BadRequest('extraPrice 非法');
      throw e;
    }
  },

  createDish(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const {
      merchantId,
      name,
      price,
      mealType,
      image,
      description,
      tags,
      sortOrder,
      category,
      extraPrice,
      mealTypes,
    } = req.body ?? {};
    if (!merchantId || !name || !mealType) {
      throw BadRequest('merchantId / name / mealType 不能为空');
    }
    if (!ALL_MEAL_TYPES.includes(mealType)) throw BadRequest('mealType 非法');
    // 套餐体系下，普通菜品可以不单独设价（price=0 兼容）
    const normalizedPrice =
      price != null && Number.isFinite(Number(price)) && Number(price) >= 0
        ? Number(price)
        : 0;
    try {
      const row = dishService.create({
        merchantId,
        name,
        price: normalizedPrice,
        mealType,
        image,
        description,
        tags,
        sortOrder: sortOrder != null ? Number(sortOrder) : undefined,
        category,
        extraPrice: extraPrice != null ? Number(extraPrice) : undefined,
        mealTypes: Array.isArray(mealTypes) ? mealTypes : undefined,
      });
      auditAdminOperation(req, 'dish.create', {
        targetType: 'dish',
        targetId: row.id,
        detail: { merchantId, name, mealType, category },
      });
      res.json({ data: dishToDto(row) });
    } catch (e) {
      const msg = (e as Error).message;
      if (msg === 'EXTRA_PRICE_REQUIRED')
        throw BadRequest('加菜分类必须填写加菜价格 extraPrice');
      throw e;
    }
  },

  updateDish(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const { id, ...patch } = req.body ?? {};
    if (!id) throw BadRequest('id 不能为空');
    try {
      const row = dishService.update(id, {
        name: patch.name,
        image: patch.image,
        description: patch.description,
        price: patch.price != null ? Number(patch.price) : undefined,
        mealType: patch.mealType,
        tags: patch.tags,
        isAvailable: patch.isAvailable,
        isSoldOut: patch.isSoldOut,
        sortOrder: patch.sortOrder != null ? Number(patch.sortOrder) : undefined,
        category: patch.category,
        extraPrice:
          patch.extraPrice != null ? Number(patch.extraPrice) : undefined,
        mealTypes: Array.isArray(patch.mealTypes) ? patch.mealTypes : undefined,
      });
      auditAdminOperation(req, 'dish.update', {
        targetType: 'dish',
        targetId: id,
        detail: patch,
      });
      res.json({ data: dishToDto(row) });
    } catch (e) {
      const msg = (e as Error).message;
      if (msg === 'NOT_FOUND') throw NotFound('菜品不存在');
      if (msg === 'EXTRA_PRICE_REQUIRED')
        throw BadRequest('切换为加菜分类必须填写加菜价格 extraPrice');
      if (msg === 'INVALID_EXTRA_PRICE') throw BadRequest('extraPrice 非法');
      throw e;
    }
  },

  updateDishById(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const patch = req.body ?? {};
    try {
      const row = dishService.update(req.params.id, {
        name: patch.name,
        image: patch.image,
        description: patch.description,
        price: patch.price != null ? Number(patch.price) : undefined,
        mealType: patch.mealType,
        tags: patch.tags,
        isAvailable: patch.isAvailable,
        isSoldOut: patch.isSoldOut,
        sortOrder: patch.sortOrder != null ? Number(patch.sortOrder) : undefined,
        category: patch.category,
        extraPrice:
          patch.extraPrice != null ? Number(patch.extraPrice) : undefined,
        mealTypes: Array.isArray(patch.mealTypes) ? patch.mealTypes : undefined,
      });
      auditAdminOperation(req, 'dish.update', {
        targetType: 'dish',
        targetId: req.params.id,
        detail: patch,
      });
      res.json({ data: dishToDto(row) });
    } catch (e) {
      const msg = (e as Error).message;
      if (msg === 'NOT_FOUND') throw NotFound('菜品不存在');
      if (msg === 'EXTRA_PRICE_REQUIRED')
        throw BadRequest('切换为加菜分类必须填写加菜价格 extraPrice');
      if (msg === 'INVALID_EXTRA_PRICE') throw BadRequest('extraPrice 非法');
      throw e;
    }
  },

  setDishAvailable(req: Request, res: Response) {
    try {
      const row = dishService.setAvailable(req.params.id, !!req.body?.isAvailable);
      res.json({ data: dishToDto(row) });
    } catch (e) {
      if ((e as Error).message === 'NOT_FOUND') throw NotFound('菜品不存在');
      throw e;
    }
  },

  setDishSoldOut(req: Request, res: Response) {
    try {
      const row = dishService.setSoldOut(req.params.id, !!req.body?.isSoldOut);
      res.json({ data: dishToDto(row) });
    } catch (e) {
      if ((e as Error).message === 'NOT_FOUND') throw NotFound('菜品不存在');
      throw e;
    }
  },

  setDishSort(req: Request, res: Response) {
    const sortOrder = Number(req.body?.sortOrder);
    if (!Number.isFinite(sortOrder)) throw BadRequest('sortOrder 非法');
    try {
      const row = dishService.setSortOrder(req.params.id, sortOrder);
      res.json({ data: dishToDto(row) });
    } catch (e) {
      if ((e as Error).message === 'NOT_FOUND') throw NotFound('菜品不存在');
      throw e;
    }
  },

  dashboard(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const date = (req.query.date as string) || todayDateStr();
    res.json({ data: mealSummaryService.dashboardStats(req.user, date) });
  },

  mealSummary(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const date = (req.query.date as string) || todayDateStr();
    const mealType = req.query.mealType as MealType;
    const merchantId = req.query.merchantId as string;
    const companyId = req.query.companyId as string | undefined;
    const status = req.query.status as string | undefined;
    if (!mealType || !ALL_MEAL_TYPES.includes(mealType)) {
      throw BadRequest('mealType 必填且合法');
    }
    if (!merchantId) throw BadRequest('merchantId 必填');
    try {
      const data = mealSummaryService.buildSummary(req.user, {
        date,
        mealType,
        merchantId,
        companyId,
        status,
      });
      res.json({ data });
    } catch (e) {
      if ((e as Error).message === 'MERCHANT_NOT_FOUND') {
        throw NotFound('商家不存在');
      }
      throw e;
    }
  },

  exportMealSummary(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const date = (req.query.date as string) || todayDateStr();
    const mealType = req.query.mealType as MealType;
    const merchantId = req.query.merchantId as string;
    if (!mealType || !merchantId) throw BadRequest('mealType 与 merchantId 必填');
    try {
      const data = mealSummaryService.buildSummary(req.user, {
        date,
        mealType,
        merchantId,
        companyId: req.query.companyId as string | undefined,
        status: req.query.status as string | undefined,
      });
      const csv = mealSummaryToCsv(data);
      auditAdminOperation(req, 'export.meal_summary', {
        targetType: 'merchant',
        targetId: merchantId,
        detail: { date, mealType },
      });
      res.setHeader('Content-Type', 'text/csv; charset=utf-8');
      res.setHeader(
        'Content-Disposition',
        `attachment; filename=meal-summary-${date}-${mealType}.csv`,
      );
      res.send('\ufeff' + csv);
    } catch (e) {
      if ((e as Error).message === 'MERCHANT_NOT_FOUND') throw NotFound('商家不存在');
      throw e;
    }
  },

  confirmMealSummary(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const { date, mealType, merchantId } = req.body ?? {};
    if (!date || !mealType || !merchantId) throw BadRequest('date / mealType / merchantId 必填');
    if (!ALL_MEAL_TYPES.includes(mealType)) throw BadRequest('mealType 非法');
    try {
      const data = mealSummaryService.confirmSummary(req.user, {
        date,
        mealType,
        merchantId,
      });
      res.json({ data });
    } catch (e) {
      if ((e as Error).message === 'FORBIDDEN') throw Unauthorized('无权操作');
      throw e;
    }
  },

  exportLabelsHtml(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const date = (req.query.date as string) || todayDateStr();
    const mealType = req.query.mealType as MealType;
    const merchantId = req.query.merchantId as string;
    if (!mealType || !merchantId) throw BadRequest('mealType 与 merchantId 必填');
    const config = adminService.getSystemConfig();
    const groups = mealSummaryService.listLabels(req.user, {
      date,
      mealType,
      merchantId,
      companyId: req.query.companyId as string | undefined,
    });
    const widthMm = req.query.widthMm
      ? Number(req.query.widthMm)
      : config.appSettings.labelPrintWidthMm ?? 60;
    const heightMm = req.query.heightMm
      ? Number(req.query.heightMm)
      : 40;
    const fontScaleRaw = (req.query.fontScale as string) || 'standard';
    const fontScale =
      fontScaleRaw === 'small' || fontScaleRaw === 'large'
        ? fontScaleRaw
        : 'standard';
    const html = labelsToHtml(groups, {
      widthMm: Number.isFinite(widthMm) ? widthMm : 60,
      heightMm: Number.isFinite(heightMm) ? heightMm : 40,
      fontScale,
    });
    auditAdminOperation(req, 'export.labels', {
      targetType: 'merchant',
      targetId: merchantId,
      detail: { date, mealType, groupCount: groups.length },
    });
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader(
      'Content-Disposition',
      `attachment; filename=labels-${date}-${mealType}.html`,
    );
    res.send(html);
  },

  listOrders(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const companyId = req.query.companyId as string | undefined;
    const mealType = req.query.mealType as MealType | undefined;
    const date = req.query.date as string | undefined;
    if (mealType && !ALL_MEAL_TYPES.includes(mealType)) {
      throw BadRequest('mealType 非法');
    }
    const list = adminService.listOrdersSummary(req.user, {
      companyId,
      mealType,
      date,
    });
    res.json({ data: list });
  },

  listLabels(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const date = (req.query.date as string) || todayDateStr();
    const mealType = req.query.mealType as MealType | undefined;
    const merchantId = req.query.merchantId as string | undefined;
    const companyId = req.query.companyId as string | undefined;

    if (mealType && merchantId) {
      if (!ALL_MEAL_TYPES.includes(mealType)) {
        throw BadRequest('mealType 非法');
      }
      const groups = mealSummaryService.listLabels(req.user, {
        date,
        mealType,
        merchantId,
        companyId,
      });
      res.json({ data: groups });
      return;
    }

    const list = adminService.listOrdersForLabels(req.user, date);
    res.json({ data: list });
  },

  getSystemConfig(_req: Request, res: Response) {
    res.json({ data: adminService.getSystemConfig() });
  },

  updateSystemConfig(req: Request, res: Response) {
    if (!req.user || req.user.role !== 'admin') {
      throw Unauthorized('仅平台管理员可修改系统配置');
    }
    const { mealDeadlines, appSettings } = req.body ?? {};
    if (
      (mealDeadlines && typeof mealDeadlines !== 'object') ||
      (appSettings && typeof appSettings !== 'object')
    ) {
      throw BadRequest('配置参数非法');
    }
    const data = adminService.updateSystemConfig({ mealDeadlines, appSettings });
    auditAdminOperation(req, 'system_config.update', {
      detail: { mealDeadlines, appSettings },
    });
    res.json({ data });
  },

  listOvertimeRosters(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const workDate = (req.query.workDate as string) || todayDateStr();
    const mealTypeRaw = (req.query.mealType as string | undefined)?.trim();
    const mealType = mealTypeRaw
      ? (parseRosterMealType(mealTypeRaw) ?? undefined)
      : undefined;
    const list = overtimeRosterService.listByDate(workDate, mealType ?? null);
    res.json({ data: list });
  },

  createOvertimeRoster(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const b = req.body ?? {};
    const { workDate, employeeName, phone, department, employeeNo, isEnabled, mealType } =
      b;
    if (!workDate || !employeeName || !phone || !department || !mealType) {
      throw BadRequest('workDate / mealType / employeeName / phone / department 必填');
    }
    const parsedMeal = parseRosterMealType(String(mealType));
    if (!parsedMeal) throw BadRequest('mealType 非法', 'INVALID_MEAL_TYPE');
    try {
      const row = overtimeRosterService.create({
        workDate: String(workDate),
        mealType: parsedMeal,
        employeeName: String(employeeName),
        phone: String(phone),
        department: String(department),
        employeeNo: employeeNo ? String(employeeNo) : undefined,
        isEnabled: isEnabled !== false,
      });
      auditAdminOperation(req, 'overtime_roster.create', { detail: { id: row.id } });
      res.json({ data: row });
    } catch (e) {
      const code = (e as Error).message;
      if (code === 'ROSTER_DUPLICATE') {
        throw BadRequest('同一天同餐段同员工已存在', 'ROSTER_DUPLICATE');
      }
      if (code === 'INVALID_MEAL_TYPE') {
        throw BadRequest('mealType 非法', 'INVALID_MEAL_TYPE');
      }
      throw e;
    }
  },

  setOvertimeRosterEnabled(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const id = req.params.id;
    const enabled = req.body?.enabled;
    if (!id) throw BadRequest('id 必填');
    if (typeof enabled !== 'boolean') throw BadRequest('enabled 必填');
    try {
      const row = overtimeRosterService.setEnabled(id, enabled);
      res.json({ data: row });
    } catch (e) {
      if ((e as Error).message === 'NOT_FOUND') throw NotFound('记录不存在');
      throw e;
    }
  },

  deleteOvertimeRoster(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const id = req.params.id;
    if (!id) throw BadRequest('id 必填');
    try {
      overtimeRosterService.delete(id);
      auditAdminOperation(req, 'overtime_roster.delete', { detail: { id } });
      res.json({ data: { ok: true } });
    } catch (e) {
      if ((e as Error).message === 'NOT_FOUND') throw NotFound('记录不存在');
      throw e;
    }
  },

  importOvertimeRosters(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const content = req.body?.content;
    const defaultDate = req.body?.workDate as string | undefined;
    if (typeof content !== 'string' || !content.trim()) {
      throw BadRequest('content 不能为空');
    }
    const result = overtimeRosterService.importText(content, defaultDate);
    auditAdminOperation(req, 'overtime_roster.import', {
      detail: { successCount: result.successCount, failCount: result.failCount },
    });
    res.json({ data: result });
  },

  listSettlements(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const status = req.query.status as string | undefined;
    const merchantId = req.query.merchantId as string | undefined;
    let rows = settlementService.listAll(status);
    if (merchantId) {
      rows = rows.filter((r) => r.merchant_id === merchantId);
    }
    res.json({ data: rows });
  },

  runSettlementCheck(_req: Request, res: Response) {
    const count = settlementService.runEligibilityCheck();
    res.json({ data: { eligibleCount: count } });
  },

  settleOrder(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const settlementId = req.body?.settlementId as string;
    if (!settlementId) throw BadRequest('settlementId 必填');
    try {
      const row = settlementService.settle(settlementId);
      auditAdminOperation(req, 'settlement.settle', {
        detail: { settlementId, orderId: row.order_id },
      });
      res.json({ data: row });
    } catch (e) {
      const msg = (e as Error).message;
      if (msg === 'SETTLEMENT_NOT_FOUND') throw NotFound('结算单不存在');
      if (msg === 'SETTLEMENT_BLOCKED') throw BadRequest('结算已冻结');
      if (msg === 'SETTLEMENT_NOT_ELIGIBLE') throw BadRequest('结算尚未到期');
      throw e;
    }
  },

  getMerchantHygieneDetail(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const merchantId = req.params.merchantId;
    if (!merchantId) throw BadRequest('merchantId 必填');
    const stats = merchantCreditService.getHygieneStats(merchantId);
    const lowReviews = (
      merchantCreditService.listLowHygieneReviews(merchantId) as ReviewRow[]
    ).map((r) => reviewToDto(r, reviewService.imagesOf(r)));
    const notices = merchantCreditService.listRemediationNotices(merchantId);
    res.json({
      data: {
        stats,
        lowReviews,
        remediationNotices: notices,
      },
    });
  },

  forceSettlementEligible(req: Request, res: Response) {
    if (process.env.NODE_ENV === 'production') {
      throw Forbidden('生产环境禁止');
    }
    const orderId = req.body?.orderId as string;
    if (!orderId) throw BadRequest('orderId 必填');
    try {
      const row = settlementService.forceEligible(orderId);
      res.json({ data: row });
    } catch (e) {
      if ((e as Error).message === 'SETTLEMENT_NOT_FOUND') {
        throw NotFound('结算单不存在');
      }
      throw e;
    }
  },
};

export const companyPublicController = {
  /** 企业自助入驻（公开） */
  register(req: Request, res: Response) {
    const { companyName, adminPhone, adminName } = req.body ?? {};
    if (!companyName || !adminPhone) {
      throw BadRequest('companyName 与 adminPhone 不能为空');
    }
    const result = companyService.create({ companyName, adminPhone, adminName });
    res.json({
      data: {
        company: result.company,
        adminUser: userToDto(result.adminUser),
      },
    });
  },
};

export const merchantOnboardingController = {
  /** 商家入驻申请 */
  register(req: Request, res: Response) {
    const {
      merchantName,
      address,
      phone,
      companyId,
      paymentQr,
      menuInit,
    } = req.body ?? {};
    if (!merchantName || !address || !phone || !companyId) {
      throw BadRequest('merchantName / address / phone / companyId 不能为空');
    }
    const dto = merchantOnboardingService.register({
      merchantName,
      address,
      phone,
      companyId,
      userId: req.user?.id,
      paymentQr,
      menuInit: !!menuInit,
    });
    res.json({ data: dto });
  },

  myApplication(req: Request, res: Response) {
    if (!req.user) throw BadRequest('需要登录');
    const merchants = merchantOnboardingService.listAllForAdmin(req.user);
    const merchant = merchants.find(
      (x) => x.user_id === req.user!.id || x.phone === req.user!.phone,
    );
    if (!merchant) throw NotFound('未找到入驻申请');
    res.json({ data: merchantOnboardingToDto(merchant) });
  },
};
