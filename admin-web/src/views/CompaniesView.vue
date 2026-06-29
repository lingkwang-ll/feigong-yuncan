<template>
  <div class="page-card">
    <h2 class="page-title">企业管理</h2>
    <div class="toolbar" v-if="auth.isPlatformAdmin">
      <el-button type="primary" @click="openCreate">新增企业</el-button>
    </div>
    <el-table :data="list" v-loading="loading" stripe>
      <el-table-column prop="companyName" label="企业名称" />
      <el-table-column prop="contactName" label="联系人" width="120" />
      <el-table-column prop="contactPhone" label="联系电话" width="140" />
      <el-table-column prop="status" label="状态" width="100">
        <template #default="{ row }">
          <el-tag :type="row.status === 'active' ? 'success' : 'info'">{{ row.status === 'active' ? '启用' : '停用' }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column prop="createdAt" label="创建时间" width="180" />
      <el-table-column label="操作" width="200" v-if="auth.isPlatformAdmin">
        <template #default="{ row }">
          <el-button link type="primary" @click="openEdit(row)">编辑</el-button>
          <el-button link :type="row.status === 'active' ? 'warning' : 'success'" @click="toggleStatus(row)">
            {{ row.status === 'active' ? '停用' : '启用' }}
          </el-button>
        </template>
      </el-table-column>
    </el-table>

    <el-dialog v-model="dialogVisible" :title="form.id ? '编辑企业' : '新增企业'" width="480px">
      <el-form label-width="100px">
        <el-form-item label="企业名称"><el-input v-model="form.companyName" /></el-form-item>
        <el-form-item v-if="!form.id" label="管理员手机"><el-input v-model="form.adminPhone" /></el-form-item>
        <el-form-item v-if="!form.id" label="管理员姓名"><el-input v-model="form.adminName" /></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" @click="save">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { onMounted, reactive, ref } from 'vue';
import { ElMessage } from 'element-plus';
import { adminApi } from '../api/admin';
import { useAuthStore } from '../stores/auth';

const auth = useAuthStore();
const list = ref([]);
const loading = ref(false);
const dialogVisible = ref(false);
const form = reactive({ id: '', companyName: '', adminPhone: '', adminName: '' });

async function load() {
  loading.value = true;
  try {
    const res = await adminApi.listCompanies();
    list.value = res.data;
  } catch (e) {
    ElMessage.error(e.message);
  } finally {
    loading.value = false;
  }
}

function openCreate() {
  Object.assign(form, { id: '', companyName: '', adminPhone: '', adminName: '' });
  dialogVisible.value = true;
}

function openEdit(row) {
  Object.assign(form, { id: row.id, companyName: row.companyName, adminPhone: '', adminName: '' });
  dialogVisible.value = true;
}

async function save() {
  try {
    if (form.id) {
      await adminApi.updateCompany({ id: form.id, companyName: form.companyName });
    } else {
      await adminApi.createCompany(form);
    }
    ElMessage.success('保存成功');
    dialogVisible.value = false;
    load();
  } catch (e) {
    ElMessage.error(e.message);
  }
}

async function toggleStatus(row) {
  const status = row.status === 'active' ? 'disabled' : 'active';
  try {
    await adminApi.updateCompany({ id: row.id, status });
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
