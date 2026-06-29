import axios from 'axios';
import client from './client';

const baseURL = import.meta.env.VITE_API_BASE_URL || '/api';

/** 静态资源 origin（去掉 /api，uploads 不在 /api 下） */
export function assetOrigin() {
  if (/^https?:\/\//i.test(baseURL)) {
    return baseURL.replace(/\/api\/?$/, '');
  }
  if (import.meta.env.PROD && typeof window !== 'undefined') {
    return window.location.origin;
  }
  const proxy = import.meta.env.VITE_DEV_API_PROXY || 'http://localhost:3000';
  return proxy.replace(/\/$/, '');
}

/**
 * 将后端返回的图片路径转为浏览器可访问的完整 URL。
 * - http(s)://... → 原样返回
 * - /uploads/... → {origin}/uploads/...
 */
export function fullImageUrl(url) {
  if (!url || typeof url !== 'string') return '';
  const trimmed = url.trim();
  if (!trimmed) return '';
  if (/^https?:\/\//i.test(trimmed)) return trimmed;
  if (trimmed.startsWith('/uploads/')) {
    return `${assetOrigin()}${trimmed}`;
  }
  if (trimmed.startsWith('uploads/')) {
    return `${assetOrigin()}/${trimmed}`;
  }
  return trimmed;
}

const PLACEHOLDER_ASSETS = new Set(['qr', 'logo', 'dish', 'cover']);

/** 是否为可预览的上传图片 URL（排除占位符 qr/logo 等） */
export function isUploadImageUrl(url) {
  if (!url || typeof url !== 'string') return false;
  const t = url.trim();
  if (!t || PLACEHOLDER_ASSETS.has(t)) return false;
  return /^https?:\/\//i.test(t) || t.startsWith('/uploads/') || t.startsWith('uploads/');
}

async function downloadFile(path, params, filename) {
  const token = localStorage.getItem('admin_token');
  const qs = new URLSearchParams(
    Object.entries(params || {}).filter(([, v]) => v != null && v !== ''),
  ).toString();
  const url = `${baseURL}${path}${qs ? `?${qs}` : ''}`;
  const res = await fetch(url, {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });
  if (!res.ok) {
    let message = '下载失败';
    try {
      const json = await res.json();
      message = json?.error?.message || message;
    } catch {
      /* ignore */
    }
    throw new Error(message);
  }
  const blob = await res.blob();
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = filename;
  a.click();
  URL.revokeObjectURL(a.href);
}

async function uploadFile(path, file, extra = {}) {
  const token = localStorage.getItem('admin_token');
  const form = new FormData();
  form.append('file', file);
  for (const [k, v] of Object.entries(extra)) {
    if (v != null) form.append(k, v);
  }
  const res = await axios.post(`${baseURL}${path}`, form, {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
    timeout: 30000,
  });
  return res.data;
}

export const adminApi = {
  login(phone, password) {
    return client.post('/admin/auth/password-login', { phone, password });
  },
  loginWithSms(phone, code) {
    return client.post('/admin/auth/login', { phone, code });
  },
  changePassword(oldPassword, newPassword) {
    return client.post('/auth/change-password', { oldPassword, newPassword });
  },
  resetUserPassword(userId) {
    return client.post(`/admin/users/${userId}/reset-password`);
  },
  sendSms(phone) {
    return client.post('/auth/sms/send', { phone, scene: 'admin_login' });
  },
  me() {
    return client.get('/admin/auth/me');
  },
  getDashboard(date) {
    return client.get('/admin/dashboard', { params: { date } });
  },
  listCompanies() {
    return client.get('/admin/companies');
  },
  createCompany(payload) {
    return client.post('/admin/companies', payload);
  },
  updateCompany(payload) {
    return client.put('/admin/companies', payload);
  },
  listEmployees() {
    return client.get('/admin/employees');
  },
  createEmployee(payload) {
    return client.post('/admin/employees', payload);
  },
  updateEmployee(id, payload) {
    return client.put(`/admin/employees/${id}`, payload);
  },
  setEmployeeEnabled(id, enabled) {
    return client.put(`/admin/employees/${id}/enabled`, { enabled });
  },
  importEmployees(rows) {
    return client.post('/admin/employees/import', { rows });
  },
  exportEmployees() {
    return downloadFile('/admin/employees/export', {}, 'employees.csv');
  },
  listMerchants(status) {
    return client.get('/admin/merchants', { params: { status } });
  },
  createMerchant(payload) {
    return client.post('/admin/merchants', payload);
  },
  updateMerchant(id, payload) {
    return client.put(`/admin/merchants/${id}`, payload);
  },
  reviewMerchant(id, status, rejectReason) {
    return client.post('/admin/merchant-onboarding/review', {
      merchantId: id,
      status,
      rejectReason,
    });
  },
  getMerchantOnboardingDetail(id) {
    return client.get(`/admin/merchant-onboarding/${id}`);
  },
  setMerchantEnabled(id, enabled) {
    return client.put(`/admin/merchants/${id}/enabled`, { enabled });
  },
  setMerchantOpen(id, isOpen) {
    return client.put(`/admin/merchants/${id}/open`, { isOpen });
  },
  updateMerchantPaymentQr(id, paymentQr) {
    return client.put(`/admin/merchants/${id}/payment-qr`, { paymentQr });
  },
  uploadDishImage(file) {
    return uploadFile('/uploads/dish-image', file);
  },
  uploadMerchantQr(file, merchantId) {
    return uploadFile('/uploads/merchant-qr-code', file, { merchantId });
  },
  listDishes(params) {
    return client.get('/admin/dishes', { params });
  },
  listCategoryMissingDishes(merchantId) {
    return client.get('/admin/dishes/category-missing', {
      params: merchantId ? { merchantId } : {},
    });
  },
  patchDishCategory(dishId, category) {
    return client.patch(`/admin/dishes/${dishId}/category`, { category });
  },
  patchDishCategoryBatch(items) {
    return client.patch('/admin/dishes/category-batch', { items });
  },
  createDish(payload) {
    return client.post('/admin/dishes', payload);
  },
  updateDish(id, payload) {
    return client.put(`/admin/dishes/${id}`, payload);
  },
  setDishAvailable(id, isAvailable) {
    return client.put(`/admin/dishes/${id}/available`, { isAvailable });
  },
  setDishSoldOut(id, isSoldOut) {
    return client.put(`/admin/dishes/${id}/sold-out`, { isSoldOut });
  },
  setDishSort(id, sortOrder) {
    return client.put(`/admin/dishes/${id}/sort`, { sortOrder });
  },
  // ===== 套餐管理（复用 /api/packages，按 merchantId 隔离） =====
  listPackages(merchantId) {
    return client.get('/packages', { params: { merchantId } });
  },
  createPackage(payload) {
    return client.post('/packages', payload);
  },
  updatePackage(id, payload) {
    return client.put(`/packages/${id}`, payload);
  },
  setPackageEnabled(id, isEnabled) {
    return client.put(`/packages/${id}/enabled`, { isEnabled });
  },
  deletePackage(id) {
    return client.delete(`/packages/${id}`);
  },
  getMealSummary(params) {
    return client.get('/admin/meal-summary', { params });
  },
  exportMealSummary(params) {
    const { date, mealType, merchantId, status } = params;
    return downloadFile(
      '/admin/meal-summary/export',
      { date, mealType, merchantId, status },
      `meal-summary-${date}-${mealType}.csv`,
    );
  },
  confirmMealSummary(payload) {
    return client.put('/admin/meal-summary/status', payload);
  },
  listLabels(params) {
    return client.get('/admin/labels', { params });
  },
  exportLabelsHtml(params) {
    const { date, mealType, merchantId, widthMm, heightMm, fontScale } = params;
    return downloadFile(
      '/admin/labels/export-html',
      { date, mealType, merchantId, widthMm, heightMm, fontScale },
      `labels-${date}-${mealType}.html`,
    );
  },
  getSystemConfig() {
    return client.get('/admin/system-config');
  },
  updateSystemConfig(payload) {
    return client.put('/admin/system-config', payload);
  },
  getDeliveryLocation({ date, mealType, merchantId }) {
    return client.get('/admin/delivery-location/current', {
      params: { date, mealType, merchantId },
    });
  },
  listOvertimeRosters(params) {
    return client.get('/admin/overtime-rosters', { params });
  },
  createOvertimeRoster(payload) {
    return client.post('/admin/overtime-rosters', payload);
  },
  setOvertimeRosterEnabled(id, enabled) {
    return client.put(`/admin/overtime-rosters/${id}/enabled`, { enabled });
  },
  deleteOvertimeRoster(id) {
    return client.delete(`/admin/overtime-rosters/${id}`);
  },
  importOvertimeRosters(payload) {
    return client.post('/admin/overtime-rosters/import', payload);
  },
  listSettlements(status) {
    return client.get('/admin/settlements', {
      params: status ? { status } : {},
    });
  },
  runSettlementCheck() {
    return client.post('/admin/settlements/check', {});
  },
  settleOrder(settlementId) {
    return client.post('/admin/settlements/settle', { settlementId });
  },
  getMerchantHygiene(merchantId) {
    return client.get(`/admin/merchants/${merchantId}/hygiene`);
  },
  listSupportConversations() {
    return client.get('/admin/support/conversations');
  },
  getSupportUnreadCount() {
    return client.get('/admin/support/unread-count');
  },
  listSupportMessages(conversationId) {
    return client.get(`/admin/support/conversations/${conversationId}/messages`);
  },
  sendSupportMessage(conversationId, body) {
    return client.post(`/admin/support/conversations/${conversationId}/messages`, body);
  },
  markSupportRead(conversationId) {
    return client.post(`/admin/support/conversations/${conversationId}/read`);
  },
  updateSupportStatus(conversationId, status) {
    return client.patch(`/admin/support/conversations/${conversationId}/status`, { status });
  },
  async uploadSupportImage(file, conversationId) {
    const token = localStorage.getItem('admin_token');
    const form = new FormData();
    form.append('file', file);
    if (conversationId) form.append('conversationId', conversationId);
    const res = await fetch(`${baseURL}/uploads/support-image`, {
      method: 'POST',
      headers: token ? { Authorization: `Bearer ${token}` } : {},
      body: form,
    });
    const json = await res.json();
    if (!res.ok) throw new Error(json?.error?.message || '上传失败');
    return json.data;
  },
  listCoupons(params = {}) {
    return client.get('/admin/coupons', { params });
  },
  setCouponStatus(couponId, enabled) {
    return client.patch(`/admin/coupons/${couponId}/status`, { enabled });
  },
  listMerchantAgreements(params = {}) {
    return client.get('/admin/merchant-agreements', { params });
  },
  exportMerchantAgreements(params = {}) {
    return downloadFile(
      '/admin/merchant-agreements/export',
      params,
      'merchant-agreements.csv',
    );
  },
};

export const MEAL_OPTIONS = [
  { label: '早餐', value: 'breakfast' },
  { label: '中餐', value: 'lunch' },
  { label: '晚餐', value: 'dinner' },
  { label: '加班餐', value: 'overtime' },
];

export const DISH_CATEGORY_OPTIONS = [
  { label: '荤菜', value: 'meat' },
  { label: '素菜', value: 'vegetable' },
  { label: '主食', value: 'staple' },
  { label: '汤品', value: 'soup' },
  { label: '饮品', value: 'drink' },
  { label: '加菜', value: 'extra' },
];

export function dishCategoryLabel(v) {
  return DISH_CATEGORY_OPTIONS.find((c) => c.value === v)?.label || (v || '—');
}

export function todayStr() {
  const d = new Date();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${d.getFullYear()}-${m}-${day}`;
}

export function downloadCsv(filename, content) {
  const blob = new Blob(['\ufeff' + content], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

export function mealLabel(value) {
  return MEAL_OPTIONS.find((m) => m.value === value)?.label || value;
}
