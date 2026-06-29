<template>
  <div class="page-card">
    <h2 class="page-title">企业代付名单</h2>
    <p class="page-desc">
      用于配置某天某餐段享受企业代付的员工名单。员工下单时，系统会根据登录账号自动判断是否企业代付（每人每餐段最多补贴 ¥12）。
    </p>

    <div class="toolbar">
      <el-date-picker
        v-model="workDate"
        type="date"
        value-format="YYYY-MM-DD"
        placeholder="选择日期"
      />
      <el-select v-model="mealType" placeholder="餐段" style="width: 120px">
        <el-option label="全部餐段" value="" />
        <el-option label="早餐" value="breakfast" />
        <el-option label="中餐" value="lunch" />
        <el-option label="晚餐" value="dinner" />
      </el-select>
      <el-button type="primary" @click="load">查询</el-button>
      <el-button type="primary" plain @click="openCreate">新增人员</el-button>
      <el-button @click="importVisible = true">导入名单</el-button>
      <el-button @click="load">刷新</el-button>
    </div>

    <el-table :data="list" v-loading="loading" stripe>
      <el-table-column label="餐段" width="80">
        <template #default="{ row }">{{ mealLabel(row.mealType) }}</template>
      </el-table-column>
      <el-table-column prop="employeeName" label="姓名" min-width="100" />
      <el-table-column prop="phone" label="手机号" width="130" />
      <el-table-column prop="department" label="部门" min-width="110" />
      <el-table-column label="企业代付资格" width="120">
        <template #default="{ row }">
          <el-tag :type="row.isEnabled ? 'success' : 'info'" size="small">
            {{ row.isEnabled ? '有效' : '已停用' }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column label="使用状态" width="100">
        <template #default="{ row }">
          <el-tag :type="row.usageStatus === 'used' ? 'warning' : 'info'" size="small">
            {{ row.usageStatus === 'used' ? '已使用' : '未使用' }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column label="操作" width="220" fixed="right">
        <template #default="{ row }">
          <el-button link type="primary" @click="openDetail(row)">查看</el-button>
          <el-button link type="warning" @click="toggleEnabled(row)">
            {{ row.isEnabled ? '停用' : '启用' }}
          </el-button>
          <el-button link type="danger" @click="removeRow(row)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>

    <el-dialog v-model="dialogVisible" title="新增名单人员" width="440px">
      <el-form label-width="100px">
        <el-form-item label="日期" required>
          <el-date-picker
            v-model="form.workDate"
            type="date"
            value-format="YYYY-MM-DD"
            style="width: 100%"
          />
        </el-form-item>
        <el-form-item label="餐段" required>
          <el-select v-model="form.mealType" style="width: 100%">
            <el-option label="早餐" value="breakfast" />
            <el-option label="中餐" value="lunch" />
            <el-option label="晚餐" value="dinner" />
          </el-select>
        </el-form-item>
        <el-form-item label="姓名" required>
          <el-input v-model="form.employeeName" />
        </el-form-item>
        <el-form-item label="手机号" required>
          <el-input v-model="form.phone" maxlength="11" />
        </el-form-item>
        <el-form-item label="部门" required>
          <el-input v-model="form.department" placeholder="如：生产部" />
        </el-form-item>
        <el-form-item label="员工编号">
          <el-input v-model="form.employeeNo" placeholder="选填，用于辅助匹配" />
        </el-form-item>
        <el-form-item label="是否启用">
          <el-switch v-model="form.isEnabled" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="submitCreate">保存</el-button>
      </template>
    </el-dialog>

    <el-dialog v-model="detailVisible" title="名单详情" width="520px">
      <el-descriptions v-if="detailRow" :column="1" border>
        <el-descriptions-item label="日期">{{ detailRow.workDate }}</el-descriptions-item>
        <el-descriptions-item label="餐段">{{ mealLabel(detailRow.mealType) }}</el-descriptions-item>
        <el-descriptions-item label="姓名">{{ detailRow.employeeName }}</el-descriptions-item>
        <el-descriptions-item label="手机号">{{ detailRow.phone }}</el-descriptions-item>
        <el-descriptions-item label="部门">{{ detailRow.department }}</el-descriptions-item>
        <el-descriptions-item label="员工编号">
          {{ detailRow.employeeNo || '—' }}
        </el-descriptions-item>
        <el-descriptions-item label="来源">
          {{ detailRow.source === 'import' ? '导入' : '手动' }}
        </el-descriptions-item>
        <el-descriptions-item label="状态">
          {{ detailRow.isEnabled ? '有效' : '已停用' }}
        </el-descriptions-item>
        <el-descriptions-item label="是否已使用">
          {{ detailRow.usageStatus === 'used' ? '已使用' : '未使用' }}
        </el-descriptions-item>
        <el-descriptions-item label="企业代付额度">
          ¥{{ detailRow.companyPaySubsidyCap ?? 12 }}
        </el-descriptions-item>
        <el-descriptions-item label="使用商家">
          {{ detailRow.usageStatus === 'used' ? (detailRow.usageMerchantName || '—') : '未使用' }}
        </el-descriptions-item>
        <el-descriptions-item label="使用订单">
          {{ detailRow.usageStatus === 'used' ? (detailRow.usageOrderId || '—') : '未使用' }}
        </el-descriptions-item>
        <el-descriptions-item label="使用时间">
          {{ detailRow.usageStatus === 'used' ? formatTime(detailRow.usageAt) : '未使用' }}
        </el-descriptions-item>
        <el-descriptions-item v-if="detailRow.usageStatus === 'used'" label="订单总额">
          ¥{{ formatMoney(detailRow.usageOrderTotalAmount) }}
        </el-descriptions-item>
        <el-descriptions-item v-if="detailRow.usageStatus === 'used'" label="实际企业代付">
          ¥{{ formatMoney(detailRow.usageCompanyPayAmount) }}
        </el-descriptions-item>
        <el-descriptions-item v-if="detailRow.usageStatus === 'used'" label="员工自付">
          ¥{{ formatMoney(detailRow.usageEmployeePayAmount) }}
        </el-descriptions-item>
        <el-descriptions-item label="创建时间">
          {{ formatTime(detailRow.createdAt) }}
        </el-descriptions-item>
        <el-descriptions-item label="备注">—</el-descriptions-item>
      </el-descriptions>
      <template #footer>
        <el-button @click="detailVisible = false">关闭</el-button>
      </template>
    </el-dialog>

    <el-dialog v-model="importVisible" title="导入企业代付名单" width="520px">
      <p class="hint">
        支持 CSV / Excel 另存为 CSV。列格式：日期,餐段,姓名,手机号,部门,员工编号（选填）。
        若不含日期列，将使用上方所选日期；餐段填早餐/中餐/晚餐。
        来源、使用状态等由系统自动生成，无需填写。
      </p>
      <el-upload
        drag
        :auto-upload="false"
        :limit="1"
        accept=".csv,.txt"
        :on-change="onFileChange"
      >
        <div class="el-upload__text">拖拽或点击选择 CSV 文件</div>
      </el-upload>
      <el-input
        v-model="importText"
        type="textarea"
        :rows="6"
        placeholder="或直接粘贴 CSV 内容"
        class="import-text"
      />
      <template #footer>
        <el-button @click="importVisible = false">取消</el-button>
        <el-button type="primary" :loading="importing" @click="submitImport">导入</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { onMounted, reactive, ref } from 'vue';
import { ElMessage, ElMessageBox } from 'element-plus';
import { adminApi, todayStr } from '../api/admin';

const workDate = ref(todayStr());
const mealType = ref('');
const list = ref([]);
const loading = ref(false);
const dialogVisible = ref(false);
const detailVisible = ref(false);
const detailRow = ref(null);
const importVisible = ref(false);
const saving = ref(false);
const importing = ref(false);
const importText = ref('');

const form = reactive({
  workDate: todayStr(),
  mealType: 'lunch',
  employeeName: '',
  phone: '',
  department: '',
  employeeNo: '',
  isEnabled: true,
});

function mealLabel(mt) {
  if (mt === 'breakfast') return '早餐';
  if (mt === 'dinner') return '晚餐';
  return '中餐';
}

function formatTime(value) {
  if (!value) return '—';
  try {
    return new Date(value).toLocaleString('zh-CN', { hour12: false });
  } catch {
    return value;
  }
}

function formatMoney(value) {
  const n = Number(value ?? 0);
  return Number.isFinite(n) ? n.toFixed(2) : '0.00';
}

async function load() {
  loading.value = true;
  try {
    const params = { workDate: workDate.value };
    if (mealType.value) params.mealType = mealType.value;
    const res = await adminApi.listOvertimeRosters(params);
    list.value = res.data || [];
  } catch (e) {
    ElMessage.error(e.message || '加载失败');
  } finally {
    loading.value = false;
  }
}

function openCreate() {
  form.workDate = workDate.value;
  form.mealType = mealType.value || 'lunch';
  form.employeeName = '';
  form.phone = '';
  form.department = '';
  form.employeeNo = '';
  form.isEnabled = true;
  dialogVisible.value = true;
}

function openDetail(row) {
  detailRow.value = row;
  detailVisible.value = true;
}

async function submitCreate() {
  if (!form.workDate || !form.mealType || !form.employeeName || !form.phone || !form.department) {
    ElMessage.warning('请填写必填项');
    return;
  }
  saving.value = true;
  try {
    await adminApi.createOvertimeRoster({ ...form });
    ElMessage.success('已添加');
    dialogVisible.value = false;
    load();
  } catch (e) {
    ElMessage.error(e.message || '保存失败');
  } finally {
    saving.value = false;
  }
}

async function toggleEnabled(row) {
  try {
    await adminApi.setOvertimeRosterEnabled(row.id, !row.isEnabled);
    ElMessage.success('已更新');
    load();
  } catch (e) {
    ElMessage.error(e.message || '操作失败');
  }
}

async function removeRow(row) {
  try {
    await ElMessageBox.confirm(`确定删除 ${row.employeeName} 的名单记录？`, '确认');
    await adminApi.deleteOvertimeRoster(row.id);
    ElMessage.success('已删除');
    load();
  } catch (e) {
    if (e !== 'cancel') ElMessage.error(e.message || '删除失败');
  }
}

function onFileChange(file) {
  const reader = new FileReader();
  reader.onload = () => {
    importText.value = String(reader.result || '');
  };
  reader.readAsText(file.raw, 'UTF-8');
}

async function submitImport() {
  if (!importText.value.trim()) {
    ElMessage.warning('请选择文件或粘贴内容');
    return;
  }
  importing.value = true;
  try {
    const res = await adminApi.importOvertimeRosters({
      workDate: workDate.value,
      content: importText.value,
    });
    const d = res.data || {};
    ElMessage.success(`导入成功 ${d.successCount || 0} 条，失败 ${d.failCount || 0} 条`);
    if (d.failures?.length) {
      console.warn('import failures', d.failures);
    }
    importVisible.value = false;
    importText.value = '';
    load();
  } catch (e) {
    ElMessage.error(e.message || '导入失败');
  } finally {
    importing.value = false;
  }
}

onMounted(load);
</script>

<style scoped>
.page-desc {
  font-size: 13px;
  color: #666;
  margin: -8px 0 16px;
  line-height: 1.6;
}
.hint {
  font-size: 13px;
  color: #666;
  margin-bottom: 12px;
  line-height: 1.5;
}
.import-text {
  margin-top: 12px;
}
</style>
