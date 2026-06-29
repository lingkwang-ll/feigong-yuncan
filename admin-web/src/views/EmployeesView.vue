<template>

  <div class="page-card">

    <h2 class="page-title">员工管理</h2>

    <div class="toolbar">

      <el-button type="primary" @click="openCreate">新增员工</el-button>

      <el-button @click="openImport">批量导入</el-button>

      <el-button @click="exportList">导出列表</el-button>

    </div>

    <el-table :data="list" v-loading="loading" stripe>

      <el-table-column label="姓名" min-width="120">

        <template #default="{ row }">

          <span>{{ row.name }}</span>

          <el-tag v-if="row.status !== 'active'" size="small" type="info" class="status-tag">已停用</el-tag>

        </template>

      </el-table-column>

      <el-table-column prop="phone" label="手机号" width="140" />

      <el-table-column prop="departmentName" label="部门" min-width="120" />

      <el-table-column label="操作" width="220" fixed="right">

        <template #default="{ row }">

          <el-button link type="primary" @click="openEdit(row)">编辑</el-button>

          <el-button link type="warning" @click="toggleStatus(row)">

            {{ row.status === 'active' ? '停用' : '启用' }}

          </el-button>

          <el-button link @click="resetPassword(row)">重置密码</el-button>

        </template>

      </el-table-column>

    </el-table>



    <el-dialog v-model="dialogVisible" :title="form.userId ? '编辑员工' : '新增员工'" width="420px">

      <el-form label-width="80px">

        <el-form-item label="姓名" required>

          <el-input v-model="form.name" placeholder="请输入姓名" />

        </el-form-item>

        <el-form-item label="手机号" required>

          <el-input v-model="form.phone" placeholder="11 位手机号" maxlength="11" />

        </el-form-item>

        <el-form-item label="部门">

          <el-input v-model="form.departmentName" placeholder="如：行政部" />

        </el-form-item>

        <el-form-item v-if="form.userId" label="启用">

          <el-switch v-model="form.enabled" active-text="启用" inactive-text="停用" />

        </el-form-item>

      </el-form>

      <template #footer>

        <el-button @click="dialogVisible = false">取消</el-button>

        <el-button type="primary" @click="save">保存</el-button>

      </template>

    </el-dialog>



    <el-dialog v-model="importVisible" title="批量导入" width="640px" @closed="resetImport">

      <div class="import-toolbar">

        <el-button @click="downloadTemplate">下载导入模板</el-button>

        <el-upload

          :auto-upload="false"

          :show-file-list="false"

          accept=".csv,.xlsx,.xls"

          :on-change="onFileChange"

        >

          <el-button type="primary">选择 Excel / CSV 文件</el-button>

        </el-upload>

      </div>

      <p class="hint">模板字段：姓名、手机号、部门（仅三列）</p>

      <p v-if="importFileName" class="hint">已选文件：{{ importFileName }}</p>

      <el-table v-if="importPreview.length" :data="importPreview" max-height="320" stripe size="small" class="preview-table">

        <el-table-column prop="name" label="姓名" width="100">

          <template #default="{ row }">

            <span :class="{ 'cell-error': row.error }">{{ row.name || '—' }}</span>

          </template>

        </el-table-column>

        <el-table-column prop="phone" label="手机号" width="130">

          <template #default="{ row }">

            <span :class="{ 'cell-error': row.error }">{{ row.phone || '—' }}</span>

          </template>

        </el-table-column>

        <el-table-column prop="departmentName" label="部门" min-width="100">

          <template #default="{ row }">

            <span :class="{ 'cell-error': row.error }">{{ row.departmentName || '—' }}</span>

          </template>

        </el-table-column>

        <el-table-column prop="error" label="说明" min-width="140">

          <template #default="{ row }">

            <span v-if="row.error" class="cell-error">{{ row.error }}</span>

            <span v-else class="cell-ok">可导入</span>

          </template>

        </el-table-column>

      </el-table>

      <p v-if="importPreview.length && importInvalidCount" class="hint error-hint">

        共 {{ importInvalidCount }} 行格式有误，请修正后重新上传；确认导入时将跳过错误行。

      </p>

      <template #footer>

        <el-button @click="importVisible = false">取消</el-button>

        <el-button

          type="primary"

          :disabled="!importValidRows.length"

          :loading="importing"

          @click="confirmImport"

        >

          确认导入（{{ importValidRows.length }} 条）

        </el-button>

      </template>

    </el-dialog>

  </div>

</template>



<script setup>

import { computed, onMounted, reactive, ref } from 'vue';

import { ElMessage, ElMessageBox } from 'element-plus';

import * as XLSX from 'xlsx';

import { adminApi, downloadCsv } from '../api/admin';

import { useAuthStore } from '../stores/auth';



const auth = useAuthStore();

const list = ref([]);

const loading = ref(false);

const dialogVisible = ref(false);

const importVisible = ref(false);

const importPreview = ref([]);

const importFileName = ref('');

const importing = ref(false);



const form = reactive({

  userId: '',

  name: '',

  phone: '',

  departmentName: '',

  enabled: true,

});



const PHONE_RE = /^1[3-9]\d{9}$/;



function defaultCompanyId() {

  return auth.user?.companyId || 'comp_default';

}



function normalizePhone(v) {

  return String(v ?? '').replace(/\s/g, '');

}



function isValidPhone(v) {

  return PHONE_RE.test(normalizePhone(v));

}



const importValidRows = computed(() =>

  importPreview.value.filter((r) => !r.error).map(({ name, phone, departmentName }) => ({

    name,

    phone: normalizePhone(phone),

    departmentName: departmentName || '未分配',

  })),

);



const importInvalidCount = computed(() =>

  importPreview.value.filter((r) => r.error).length,

);



async function load() {

  loading.value = true;

  try {

    const res = await adminApi.listEmployees();

    list.value = res.data;

  } catch (e) {

    ElMessage.error(e.message);

  } finally {

    loading.value = false;

  }

}



function openCreate() {

  Object.assign(form, {

    userId: '',

    name: '',

    phone: '',

    departmentName: '',

    enabled: true,

  });

  dialogVisible.value = true;

}



function openEdit(row) {

  Object.assign(form, {

    userId: row.id,

    name: row.name,

    phone: row.phone,

    departmentName: row.departmentName === '—' ? '' : row.departmentName,

    enabled: row.status === 'active',

  });

  dialogVisible.value = true;

}



async function save() {

  const name = form.name.trim();

  const phone = normalizePhone(form.phone);

  const departmentName = form.departmentName.trim() || '未分配';

  if (!name) {

    ElMessage.warning('请填写姓名');

    return;

  }

  if (!isValidPhone(phone)) {

    ElMessage.warning('手机号格式不正确');

    return;

  }

  try {

    if (form.userId) {

      await adminApi.updateEmployee(form.userId, {

        name,

        phone,

        departmentName,

        status: form.enabled ? 'active' : 'disabled',

      });

    } else {

      await adminApi.createEmployee({

        name,

        phone,

        departmentName,

        role: 'employee',

        companyId: defaultCompanyId(),

        canOrder: true,

        status: 'active',

      });

    }

    ElMessage.success(form.userId ? '保存成功' : '员工初始密码为 123456，请首次登录后修改');

    dialogVisible.value = false;

    load();

  } catch (e) {

    ElMessage.error(e.message);

  }

}



async function toggleStatus(row) {

  const enabled = row.status !== 'active';

  try {

    await adminApi.setEmployeeEnabled(row.id, enabled);

    ElMessage.success('已更新');

    load();

  } catch (e) {

    ElMessage.error(e.message);

  }

}



async function resetPassword(row) {

  try {

    await ElMessageBox.confirm(

      '是否将该员工密码重置为 123456？',

      '重置密码',

      { type: 'warning' },

    );

    await adminApi.resetUserPassword(row.id);

    ElMessage.success('密码已重置为 123456');

  } catch (e) {

    if (e !== 'cancel') ElMessage.error(e.message || '操作失败');

  }

}



async function exportList() {

  try {

    await adminApi.exportEmployees();

    ElMessage.success('导出成功');

  } catch (e) {

    ElMessage.error(e.message);

  }

}



function downloadTemplate() {

  const content = [

    '姓名,手机号,部门',

    '张三,13800000000,行政部',

    '李四,13800000001,销售部',

    '王五,13800000002,生产部',

  ].join('\n');

  downloadCsv('员工导入模板.csv', content);

}



function openImport() {

  resetImport();

  importVisible.value = true;

}



function resetImport() {

  importPreview.value = [];

  importFileName.value = '';

  importing.value = false;

}



function headerKey(cell) {

  const s = String(cell ?? '').trim().toLowerCase();

  if (['姓名', 'name'].includes(s)) return 'name';

  if (['手机号', 'phone', '手机', '电话'].includes(s)) return 'phone';

  if (['部门', 'department', 'departmentname'].includes(s)) return 'department';

  return null;

}



function parseSheetRows(rawRows) {

  if (!rawRows.length) return [];

  const first = rawRows[0].map((c) => String(c ?? '').trim());

  const mapped = first.map(headerKey);

  const hasHeader = mapped.some(Boolean);

  const start = hasHeader ? 1 : 0;

  let nameIdx = 0;

  let phoneIdx = 1;

  let deptIdx = 2;

  if (hasHeader) {

    nameIdx = mapped.indexOf('name');

    phoneIdx = mapped.indexOf('phone');

    deptIdx = mapped.indexOf('department');

    if (nameIdx < 0) nameIdx = 0;

    if (phoneIdx < 0) phoneIdx = 1;

    if (deptIdx < 0) deptIdx = 2;

  }

  const result = [];

  for (let i = start; i < rawRows.length; i++) {

    const row = rawRows[i];

    if (!row || row.every((c) => String(c ?? '').trim() === '')) continue;

    const name = String(row[nameIdx] ?? '').trim();

    const phone = normalizePhone(row[phoneIdx]);

    const departmentName = String(row[deptIdx] ?? '').trim() || '未分配';

    let error = '';

    if (!name) error = '姓名不能为空';

    else if (!phone) error = '手机号不能为空';

    else if (!isValidPhone(phone)) error = '手机号格式不正确';

    result.push({ name, phone, departmentName, error });

  }

  return result;

}



function parseCsvText(text) {

  const lines = text.split(/\r?\n/).filter((l) => l.trim());

  const rows = lines.map((line) => {

    const parts = [];

    let cur = '';

    let inQuote = false;

    for (let i = 0; i < line.length; i++) {

      const ch = line[i];

      if (ch === '"') {

        inQuote = !inQuote;

      } else if (ch === ',' && !inQuote) {

        parts.push(cur);

        cur = '';

      } else {

        cur += ch;

      }

    }

    parts.push(cur);

    return parts.map((s) => s.trim().replace(/^"|"$/g, ''));

  });

  return parseSheetRows(rows);

}



async function onFileChange(uploadFile) {

  const file = uploadFile.raw;

  if (!file) return;

  importFileName.value = file.name;

  try {

    const ext = file.name.split('.').pop()?.toLowerCase();

    if (ext === 'csv') {

      const text = await file.text();

      importPreview.value = parseCsvText(text);

    } else if (ext === 'xlsx' || ext === 'xls') {

      const buf = await file.arrayBuffer();

      const wb = XLSX.read(buf, { type: 'array' });

      const sheet = wb.Sheets[wb.SheetNames[0]];

      const raw = XLSX.utils.sheet_to_json(sheet, { header: 1, defval: '' });

      importPreview.value = parseSheetRows(raw);

    } else {

      ElMessage.warning('仅支持 .csv / .xlsx / .xls 文件');

      return;

    }

    if (!importPreview.value.length) {

      ElMessage.warning('文件中没有可导入的数据');

    }

  } catch (e) {

    ElMessage.error('文件解析失败：' + e.message);

    importPreview.value = [];

  }

}



async function confirmImport() {

  if (!importValidRows.value.length) {

    ElMessage.warning('没有可导入的有效数据');

    return;

  }

  importing.value = true;

  try {

    const res = await adminApi.importEmployees(importValidRows.value);

    const { created = 0, updated = 0, skipped = 0 } = res.data || {};

    ElMessage.success(`导入完成：新增 ${created}，更新 ${updated}，跳过 ${skipped}`);

    importVisible.value = false;

    load();

  } catch (e) {

    ElMessage.error(e.message);

  } finally {

    importing.value = false;

  }

}



onMounted(load);

</script>



<style scoped>

.toolbar {

  display: flex;

  gap: 12px;

  margin-bottom: 16px;

  flex-wrap: wrap;

}

.hint {

  color: #888;

  font-size: 13px;

  margin: 8px 0;

}

.error-hint {

  color: #e6a23c;

}

.import-toolbar {

  display: flex;

  gap: 12px;

  margin-bottom: 8px;

  flex-wrap: wrap;

}

.preview-table {

  margin-top: 8px;

}

.status-tag {

  margin-left: 8px;

  vertical-align: middle;

}

.cell-error {

  color: #f56c6c;

}

.cell-ok {

  color: #67c23a;

  font-size: 12px;

}

</style>

