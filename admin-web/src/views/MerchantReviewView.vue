<template>
  <div class="page-card">
    <h2 class="page-title">商家审核中心</h2>
    <div class="toolbar">
      <el-radio-group v-model="status" @change="load">
        <el-radio-button label="">全部</el-radio-button>
        <el-radio-button label="pending">待审核</el-radio-button>
        <el-radio-button label="approved">已通过</el-radio-button>
        <el-radio-button label="rejected">已拒绝</el-radio-button>
      </el-radio-group>
    </div>
    <el-table :data="list" v-loading="loading" stripe>
      <el-table-column prop="merchantName" label="商家名称" />
      <el-table-column prop="address" label="地址" />
      <el-table-column prop="phone" label="联系电话" width="130" />
      <el-table-column prop="companyId" label="企业 ID" width="140" />
      <el-table-column prop="status" label="审核状态" width="100" />
      <el-table-column label="操作" width="260">
        <template #default="{ row }">
          <template v-if="row.status === 'pending'">
            <el-button size="small" type="success" @click="review(row, 'approved')">通过</el-button>
            <el-button size="small" type="danger" @click="review(row, 'rejected')">拒绝</el-button>
          </template>
          <template v-else-if="row.status === 'approved'">
            <el-button size="small" @click="setEnabled(row, false)">禁用</el-button>
            <el-button size="small" type="primary" @click="setEnabled(row, true)">启用</el-button>
          </template>
        </template>
      </el-table-column>
    </el-table>
  </div>
</template>

<script setup>
import { onMounted, ref } from 'vue';
import { ElMessage } from 'element-plus';
import { adminApi } from '../api/admin';

const list = ref([]);
const loading = ref(false);
const status = ref('pending');

async function load() {
  loading.value = true;
  try {
    const res = await adminApi.listMerchants(status.value || undefined);
    list.value = res.data;
  } catch (e) {
    ElMessage.error(e.message);
  } finally {
    loading.value = false;
  }
}

async function review(row, s) {
  try {
    await adminApi.reviewMerchant(row.id, s);
    ElMessage.success('审核完成');
    load();
  } catch (e) {
    ElMessage.error(e.message);
  }
}

async function setEnabled(row, enabled) {
  try {
    await adminApi.setMerchantEnabled(row.id, enabled);
    ElMessage.success('已更新');
    load();
  } catch (e) {
    ElMessage.error(e.message);
  }
}

onMounted(load);
</script>

<style scoped>
.toolbar { margin-bottom: 16px; }
</style>
