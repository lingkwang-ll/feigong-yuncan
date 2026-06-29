import { createRouter, createWebHistory } from 'vue-router';
import { useAuthStore } from '../stores/auth';

const routes = [
  {
    path: '/login',
    name: 'login',
    component: () => import('../views/LoginView.vue'),
    meta: { public: true },
  },
  {
    path: '/',
    component: () => import('../layouts/AdminLayout.vue'),
    redirect: '/dashboard',
    children: [
      { path: 'dashboard', component: () => import('../views/DashboardView.vue') },
      { path: 'companies', component: () => import('../views/CompaniesView.vue') },
      { path: 'employees', component: () => import('../views/EmployeesView.vue') },
      { path: 'overtime-rosters', component: () => import('../views/OvertimeRosterView.vue') },
      { path: 'settlements', component: () => import('../views/SettlementView.vue') },
      { path: 'merchants', component: () => import('../views/MerchantsView.vue') },
      { path: 'dishes', component: () => import('../views/DishesView.vue') },
      { path: 'dishes/category-missing', component: () => import('../views/CategoryMissingView.vue') },
      { path: 'meal-summary', component: () => import('../views/MealSummaryView.vue') },
      { path: 'labels', component: () => import('../views/LabelsView.vue') },
      { path: 'coupons', component: () => import('../views/CouponsView.vue') },
      { path: 'merchant-agreements', component: () => import('../views/MerchantAgreementsView.vue') },
      { path: 'support-messages', component: () => import('../views/SupportMessagesView.vue') },
      { path: 'system-config', component: () => import('../views/SystemConfigView.vue') },
    ],
  },
];

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes,
});

router.beforeEach((to) => {
  const auth = useAuthStore();
  if (!to.meta.public && !auth.isLoggedIn) {
    return '/login';
  }
  if (to.path === '/login' && auth.isLoggedIn) {
    return '/dashboard';
  }
  if (to.path === '/companies' && !auth.canManageCompanies) {
    return '/dashboard';
  }
  if (to.path === '/employees' && !auth.canManageEmployees) {
    return '/dashboard';
  }
  if (to.path === '/overtime-rosters' && !auth.canManageEmployees) {
    return '/dashboard';
  }
  if (to.path === '/system-config' && !auth.canManageSystemConfig) {
    return '/dashboard';
  }
  if (to.path === '/support-messages' && !auth.isPlatformAdmin && !auth.isCompanyAdmin) {
    return '/dashboard';
  }
});

export default router;
