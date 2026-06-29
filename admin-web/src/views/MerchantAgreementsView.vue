<template>
  <div class="page-card">
    <h2 class="page-title">商家协议签署记录</h2>

    <div class="toolbar">
      <el-input
        v-model="merchantFilter"
        placeholder="按商家 ID 筛选"
        clearable
        style="width: 220px"
        @keyup.enter="load"
      />
      <el-button type="primary" @click="load">查询</el-button>
      <el-button @click="resetFilter">重置</el-button>
      <el-button type="success" @click="exportCsv">导出 CSV</el-button>
    </div>

    <el-table :data="list" v-loading="loading" stripe>
      <el-table-column prop="merchantName" label="商家" min-width="120" />
      <el-table-column prop="merchantId" label="商家 ID" width="140" />
      <el-table-column prop="agreementVersion" label="协议版本" width="100" />
      <el-table-column label="签署时间" width="180">
        <template #default="{ row }">{{ formatTime(row.signedAt) }}</template>
      </el-table-column>
      <el-table-column prop="ipAddress" label="IP" width="130" />
      <el-table-column prop="userAgent" label="设备信息" min-width="160" show-overflow-tooltip />
      <el-table-column prop="signatureHash" label="签名哈希" width="120" show-overflow-tooltip />
      <el-table-column label="操作" width="100" fixed="right">
        <template #default="{ row }">
          <el-button link type="primary" @click="showContent(row)">查看协议</el-button>
        </template>
      </el-table-column>
    </el-table>

    <el-dialog v-model="dialogVisible" title="协议内容快照" width="720px">
      <div class="meta">
        <p><strong>商家：</strong>{{ current?.merchantName }}（{{ current?.merchantId }}）</p>
        <p><strong>版本：</strong>{{ current?.agreementVersion }}</p>
        <p><strong>签署时间：</strong>{{ formatTime(current?.signedAt) }}</p>
        <p><strong>IP：</strong>{{ current?.ipAddress || '—' }}</p>
        <p><strong>设备：</strong>{{ current?.userAgent || '—' }}</p>
      </div>
      <el-scrollbar max-height="420px">
        <pre class="snapshot">{{ formattedSnapshot }}</pre>
      </el-scrollbar>
    </el-dialog>
  </div>
</template>

<script setup>
import { computed, onMounted, ref } from 'vue';
import { ElMessage } from 'element-plus';
import { adminApi } from '../api/admin';

const loading = ref(false);
const list = ref([]);
const merchantFilter = ref('');
const dialogVisible = ref(false);
const current = ref(null);

const formattedSnapshot = computed(() => {
  if (!current.value?.agreementContentSnapshot) return '';
  try {
    const parsed = JSON.parse(current.value.agreementContentSnapshot);
    if (parsed.documents?.length) {
      return parsed.documents
        .map((d) => `【${d.title}】\n\n${d.body}`)
        .join('\n\n────────────\n\n');
    }
    return JSON.stringify(parsed, null, 2);
  } catch {
    return current.value.agreementContentSnapshot;
  }
});

function formatTime(v) {
  if (!v) return '—';
  return String(v).replace('T', ' ').slice(0, 19);
}

async function load() {
  loading.value = true;
  try {
    const res = await adminApi.listMerchantAgreements({
      merchantId: merchantFilter.value || undefined,
    });
    list.value = res.data || [];
  } catch (e) {
    ElMessage.error(e.message || '加载失败');
  } finally {
    loading.value = false;
  }
}

function resetFilter() {
  merchantFilter.value = '';
  load();
}

function showContent(row) {
  current.value = row;
  dialogVisible.value = true;
}

async function exportCsv() {
  try {
    await adminApi.exportMerchantAgreements({
      merchantId: merchantFilter.value || undefined,
    });
    ElMessage.success('导出已开始');
  } catch (e) {
    ElMessage.error(e.message || '导出失败');
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

.meta p {
  margin: 0 0 8px;
  font-size: 13px;
}

.snapshot {
  white-space: pre-wrap;
  word-break: break-word;
  font-size: 13px;
  line-height: 1.6;
  margin: 0;
}
</style>
