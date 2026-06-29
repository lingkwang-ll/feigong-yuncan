<template>
  <div class="page-card">
    <h2 class="page-title">系统配置</h2>

    <h3 class="section">餐段截止时间</h3>
    <el-form v-loading="loading" label-width="180px" style="max-width: 560px">
      <el-form-item v-for="item in deadlineFields" :key="item.key" :label="item.label">
        <el-time-select
          v-model="deadlines[item.key]"
          start="00:00"
          step="00:15"
          end="23:45"
          placeholder="选择时间"
          :disabled="!auth.canManageSystemConfig"
        />
      </el-form-item>
    </el-form>

    <h3 class="section">功能开关</h3>
    <el-form label-width="180px" style="max-width: 560px">
      <el-form-item label="允许员工取消订单">
        <el-switch v-model="appSettings.allowCancelOrder" :disabled="!auth.canManageSystemConfig" />
      </el-form-item>
      <el-form-item label="开启评价">
        <el-switch v-model="appSettings.enableReview" :disabled="!auth.canManageSystemConfig" />
      </el-form-item>
      <el-form-item label="商家自动刷新">
        <el-switch v-model="appSettings.enableMerchantAutoRefresh" :disabled="!auth.canManageSystemConfig" />
      </el-form-item>
      <el-form-item label="强制付款截图">
        <el-switch v-model="appSettings.requirePaymentScreenshot" :disabled="!auth.canManageSystemConfig" />
      </el-form-item>
      <el-form-item label="允许商家拒单">
        <el-switch v-model="appSettings.allowMerchantReject" :disabled="!auth.canManageSystemConfig" />
      </el-form-item>
      <el-form-item label="显示售罄菜品">
        <el-switch v-model="appSettings.showSoldOutDishes" :disabled="!auth.canManageSystemConfig" />
      </el-form-item>
    </el-form>

    <h3 class="section">标签打印</h3>
    <el-form label-width="180px" style="max-width: 560px">
      <el-form-item label="标签打印宽度 (mm)">
        <el-input-number v-model="appSettings.labelPrintWidthMm" :min="30" :max="100" :disabled="!auth.canManageSystemConfig" />
      </el-form-item>
      <el-form-item label="标签打印字体 (pt)">
        <el-input-number v-model="appSettings.labelPrintFontSizePt" :min="8" :max="24" :disabled="!auth.canManageSystemConfig" />
      </el-form-item>
      <el-form-item v-if="auth.canManageSystemConfig">
        <el-button type="primary" :loading="saving" @click="save">保存配置</el-button>
      </el-form-item>
    </el-form>
    <p v-if="!auth.canManageSystemConfig" class="hint">仅平台管理员可修改系统配置</p>
  </div>
</template>

<script setup>
import { onMounted, reactive, ref } from 'vue';
import { ElMessage } from 'element-plus';
import { adminApi } from '../api/admin';
import { useAuthStore } from '../stores/auth';

const auth = useAuthStore();
const loading = ref(false);
const saving = ref(false);
const deadlines = reactive({
  breakfast: '07:30',
  lunch: '09:30',
  dinner: '15:00',
  overtime: '17:30',
});
const appSettings = reactive({
  allowCancelOrder: true,
  enableReview: false,
  enableMerchantAutoRefresh: false,
  requirePaymentScreenshot: true,
  allowMerchantReject: true,
  showSoldOutDishes: true,
  labelPrintWidthMm: 50,
  labelPrintFontSizePt: 12,
});
const deadlineFields = [
  { key: 'breakfast', label: '早餐截止时间' },
  { key: 'lunch', label: '中餐截止时间' },
  { key: 'dinner', label: '晚餐截止时间' },
  { key: 'overtime', label: '加班餐截止时间' },
];

async function load() {
  loading.value = true;
  try {
    const res = await adminApi.getSystemConfig();
    Object.assign(deadlines, res.data.mealDeadlines);
    if (res.data.appSettings) Object.assign(appSettings, res.data.appSettings);
  } catch (e) {
    ElMessage.error(e.message);
  } finally {
    loading.value = false;
  }
}

async function save() {
  saving.value = true;
  try {
    await adminApi.updateSystemConfig({
      mealDeadlines: { ...deadlines },
      appSettings: { ...appSettings },
    });
    ElMessage.success('配置已保存');
  } catch (e) {
    ElMessage.error(e.message);
  } finally {
    saving.value = false;
  }
}

onMounted(load);
</script>

<style scoped>
.section { margin: 24px 0 12px; font-size: 15px; color: #333; }
.hint { color: #888; font-size: 13px; margin-top: 8px; }
</style>
