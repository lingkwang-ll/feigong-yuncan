<template>
  <div class="page-card">
    <h2 class="page-title">订单汇总中心</h2>
    <div class="toolbar">
      <el-date-picker v-model="date" type="date" placeholder="选择日期" value-format="YYYY-MM-DD" @change="load" />
      <el-select v-model="mealType" placeholder="餐段" clearable @change="load" style="width: 140px">
        <el-option label="早餐" value="breakfast" />
        <el-option label="中餐" value="lunch" />
        <el-option label="晚餐" value="dinner" />
        <el-option label="加班餐" value="overtime" />
      </el-select>
      <el-input v-if="auth.isPlatformAdmin" v-model="companyId" placeholder="企业 ID（可选）" style="width: 180px" @change="load" />
    </div>
    <el-table :data="list" v-loading="loading" stripe>
      <el-table-column prop="id" label="订单号" width="140" />
      <el-table-column prop="customerName" label="员工" width="100" />
      <el-table-column prop="customerCompany" label="部门" width="120" />
      <el-table-column prop="merchantName" label="商家" />
      <el-table-column prop="totalAmount" label="金额" width="80" />
      <el-table-column prop="status" label="状态" width="120" />
      <el-table-column prop="createdAt" label="时间" width="180" />
    </el-table>
  </div>
</template>

<script setup>
import { onMounted, ref } from 'vue';
import { ElMessage } from 'element-plus';
import { adminApi } from '../api/admin';
import { useAuthStore } from '../stores/auth';

const auth = useAuthStore();
const list = ref([]);
const loading = ref(false);
const date = ref('');
const mealType = ref('');
const companyId = ref('');

async function load() {
  loading.value = true;
  try {
    const res = await adminApi.listOrders({
      date: date.value || undefined,
      mealType: mealType.value || undefined,
      companyId: companyId.value || undefined,
    });
    list.value = res.data;
  } catch (e) {
    ElMessage.error(e.message);
  } finally {
    loading.value = false;
  }
}

onMounted(load);
</script>

<style scoped>
.toolbar { display: flex; gap: 12px; margin-bottom: 16px; flex-wrap: wrap; }
</style>
