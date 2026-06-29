<template>
  <div class="page-card">
    <h2 class="page-title">用户管理</h2>
    <div class="toolbar">
      <el-select v-model="role" placeholder="角色筛选" clearable @change="load">
        <el-option label="员工" value="employee" />
        <el-option label="商家" value="merchant" />
        <el-option label="企业管理员" value="company_admin" />
        <el-option label="平台管理员" value="admin" />
      </el-select>
    </div>
    <el-table :data="list" v-loading="loading" stripe>
      <el-table-column prop="name" label="姓名" />
      <el-table-column prop="phone" label="手机号" width="140" />
      <el-table-column prop="role" label="角色" width="120" />
      <el-table-column prop="companyId" label="企业 ID" width="160" />
      <el-table-column prop="status" label="状态" width="100" />
      <el-table-column label="操作" width="160">
        <template #default="{ row }">
          <el-button
            v-if="row.status === 'active'"
            size="small"
            type="danger"
            @click="toggle(row, 'disabled')"
          >禁用</el-button>
          <el-button v-else size="small" type="success" @click="toggle(row, 'active')">启用</el-button>
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
const role = ref('');

async function load() {
  loading.value = true;
  try {
    const res = await adminApi.listUsers(role.value || undefined);
    list.value = res.data;
  } catch (e) {
    ElMessage.error(e.message);
  } finally {
    loading.value = false;
  }
}

async function toggle(row, status) {
  try {
    await adminApi.setUserStatus(row.id, status);
    ElMessage.success('已更新');
    load();
  } catch (e) {
    ElMessage.error(e.message);
  }
}

onMounted(load);
</script>

<style scoped>
.toolbar { margin-bottom: 16px; width: 200px; }
</style>
