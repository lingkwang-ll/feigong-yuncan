<template>
  <el-container class="layout">
    <el-aside width="220px" class="aside">
      <div class="brand">
        <span class="logo">P+</span>
        <span>非攻云餐管理后台</span>
      </div>
      <el-menu :default-active="route.path" router background-color="#ffffff" text-color="#333">
        <el-menu-item index="/dashboard">工作台</el-menu-item>
        <el-menu-item v-if="auth.canManageCompanies" index="/companies">企业管理</el-menu-item>
        <el-menu-item v-if="auth.canManageEmployees" index="/employees">员工管理</el-menu-item>
        <el-menu-item v-if="auth.canManageEmployees" index="/overtime-rosters">企业代付名单</el-menu-item>
        <el-menu-item index="/settlements">结算管理</el-menu-item>
        <el-menu-item index="/merchants">商家管理</el-menu-item>
        <el-menu-item index="/dishes">菜品管理</el-menu-item>
        <el-menu-item index="/meal-summary">订餐汇总</el-menu-item>
        <el-menu-item index="/labels">标签打印</el-menu-item>
        <el-menu-item index="/coupons">优惠券管理</el-menu-item>
        <el-menu-item index="/merchant-agreements">协议签署记录</el-menu-item>
        <el-menu-item v-if="auth.isPlatformAdmin || auth.isCompanyAdmin" index="/support-messages">
          <span>客服消息</span>
          <el-badge
            v-if="supportUnread > 0"
            :value="supportUnread"
            class="menu-badge"
          />
        </el-menu-item>
        <el-menu-item v-if="auth.canManageSystemConfig" index="/system-config">系统配置</el-menu-item>
      </el-menu>
    </el-aside>
    <el-container>
      <el-header class="header">
        <div>{{ auth.user?.name || '管理员' }}（{{ roleLabel }}）</div>
        <div class="header-actions">
          <el-button link type="primary" @click="pwdVisible = true">修改密码</el-button>
          <el-button type="warning" @click="onLogout">退出</el-button>
        </div>
      </el-header>
      <el-main class="main">
        <router-view />
      </el-main>
    </el-container>

    <el-dialog v-model="pwdVisible" title="修改密码" width="420px">
      <el-form label-width="90px">
        <el-form-item label="原密码">
          <el-input v-model="pwdForm.oldPassword" type="password" show-password />
        </el-form-item>
        <el-form-item label="新密码">
          <el-input v-model="pwdForm.newPassword" type="password" show-password />
        </el-form-item>
        <el-form-item label="确认新密码">
          <el-input v-model="pwdForm.confirmPassword" type="password" show-password />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="pwdVisible = false">取消</el-button>
        <el-button type="primary" :loading="pwdLoading" @click="submitChangePassword">确认修改</el-button>
      </template>
    </el-dialog>
  </el-container>
</template>

<script setup>
import { computed, reactive, ref, onMounted, onUnmounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { ElMessage } from 'element-plus';
import { adminApi } from '../api/admin';
import { useAuthStore } from '../stores/auth';

const route = useRoute();
const router = useRouter();
const auth = useAuthStore();
const supportUnread = ref(0);
let supportPoll = null;
const pwdVisible = ref(false);
const pwdLoading = ref(false);
const pwdForm = reactive({
  oldPassword: '',
  newPassword: '',
  confirmPassword: '',
});

const roleLabel = computed(() => {
  if (auth.isPlatformAdmin) return '平台管理员';
  if (auth.isCompanyAdmin) return '企业管理员';
  if (auth.isMerchant) return '商家';
  return auth.user?.role || '';
});

function onLogout() {
  auth.logout();
  router.push('/login');
}

async function refreshSupportUnread() {
  if (!auth.isLoggedIn || (!auth.isPlatformAdmin && !auth.isCompanyAdmin)) return;
  try {
    const res = await adminApi.getSupportUnreadCount();
    supportUnread.value = res.data?.count ?? 0;
  } catch {
    /* ignore */
  }
}

onMounted(() => {
  refreshSupportUnread();
  supportPoll = setInterval(refreshSupportUnread, 15000);
});

onUnmounted(() => {
  if (supportPoll) clearInterval(supportPoll);
});

async function submitChangePassword() {
  if (!pwdForm.oldPassword) return ElMessage.warning('请输入原密码');
  if (!pwdForm.newPassword || pwdForm.newPassword.length < 6) {
    return ElMessage.warning('新密码至少 6 位');
  }
  if (pwdForm.newPassword !== pwdForm.confirmPassword) {
    return ElMessage.warning('两次新密码不一致');
  }
  pwdLoading.value = true;
  try {
    await adminApi.changePassword(pwdForm.oldPassword, pwdForm.newPassword);
    ElMessage.success('密码修改成功，请重新登录');
    pwdVisible.value = false;
    auth.logout();
    router.push('/login');
  } catch (e) {
    ElMessage.error(e.message);
  } finally {
    pwdLoading.value = false;
  }
}
</script>

<style scoped>
.layout { min-height: 100vh; }
.aside { background: #fff; border-right: 1px solid #eee; }
.brand {
  display: flex; align-items: center; gap: 8px;
  padding: 20px 16px; font-weight: 600; color: var(--fy-primary);
  font-size: 14px; line-height: 1.3;
}
.logo {
  width: 32px; height: 32px; border-radius: 8px; flex-shrink: 0;
  background: var(--fy-primary); color: #fff;
  display: inline-flex; align-items: center; justify-content: center;
}
.header {
  display: flex; justify-content: space-between; align-items: center;
  background: #fff; border-bottom: 1px solid #eee;
}
.header-actions { display: flex; align-items: center; gap: 8px; }
.main { background: var(--fy-bg); }
.menu-badge { margin-left: 8px; }
</style>
