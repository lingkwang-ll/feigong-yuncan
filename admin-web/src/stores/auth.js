import { defineStore } from 'pinia';
import { adminApi } from '../api/admin';

export const useAuthStore = defineStore('auth', {
  state: () => ({
    token: localStorage.getItem('admin_token') || '',
    user: JSON.parse(localStorage.getItem('admin_user') || 'null'),
  }),
  getters: {
    isLoggedIn: (s) => !!s.token,
    isPlatformAdmin: (s) => s.user?.role === 'admin',
    isCompanyAdmin: (s) => s.user?.role === 'company_admin',
    isMerchant: (s) => s.user?.role === 'merchant',
    canManageCompanies: (s) => s.user?.role === 'admin',
    canManageEmployees: (s) => ['admin', 'company_admin'].includes(s.user?.role),
    canManageSystemConfig: (s) => s.user?.role === 'admin',
  },
  actions: {
    async login(phone, password) {
      const res = await adminApi.login(phone, password);
      this.token = res.data.token;
      this.user = res.data.user;
      localStorage.setItem('admin_token', this.token);
      localStorage.setItem('admin_user', JSON.stringify(this.user));
    },
    logout() {
      this.token = '';
      this.user = null;
      localStorage.removeItem('admin_token');
      localStorage.removeItem('admin_user');
    },
    async fetchMe() {
      const res = await adminApi.me();
      this.user = res.data;
      localStorage.setItem('admin_user', JSON.stringify(this.user));
    },
  },
});
