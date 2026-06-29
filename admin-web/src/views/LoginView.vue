<template>
  <div class="login-page">
    <div class="login-card page-card">
      <h1>非攻云餐管理后台</h1>
      <p class="sub">平台 / 企业管理员登录</p>
      <el-form @submit.prevent="onLogin">
        <el-form-item label="手机号">
          <el-input v-model="phone" placeholder="请输入手机号" />
        </el-form-item>
        <el-form-item label="密码">
          <el-input v-model="password" type="password" placeholder="请输入密码" show-password />
        </el-form-item>
        <el-button type="primary" native-type="submit" :loading="loading" class="submit">
          登录
        </el-button>
      </el-form>
      <p class="hint">平台管理员默认：13700000000 / 123456</p>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue';
import { useRouter } from 'vue-router';
import { ElMessage } from 'element-plus';
import { useAuthStore } from '../stores/auth';

const phone = ref('');
const password = ref('');
const loading = ref(false);
const router = useRouter();
const auth = useAuthStore();

async function onLogin() {
  if (!phone.value) return ElMessage.warning('请输入手机号');
  if (!password.value) return ElMessage.warning('请输入密码');
  loading.value = true;
  try {
    await auth.login(phone.value, password.value);
    router.push('/');
  } catch (e) {
    ElMessage.error(e.message);
  } finally {
    loading.value = false;
  }
}
</script>

<style scoped>
.login-page {
  min-height: 100vh; display: flex; align-items: center; justify-content: center;
  background: var(--fy-bg);
}
.login-card { width: 420px; }
h1 { margin: 0 0 8px; color: var(--fy-primary); }
.sub { color: var(--fy-text-secondary); margin-bottom: 24px; }
.submit { width: 100%; margin-top: 8px; background: var(--fy-accent); border-color: var(--fy-accent); }
.hint { font-size: 12px; color: var(--fy-text-secondary); margin-top: 16px; }
</style>
