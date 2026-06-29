<template>
  <div class="page-card">
    <h2 class="page-title">标签打印中心</h2>
    <div class="toolbar">
      <el-date-picker v-model="date" type="date" value-format="YYYY-MM-DD" @change="load" />
      <el-select v-model="mealType" placeholder="餐段" style="width: 120px" @change="load">
        <el-option v-for="m in mealOptions" :key="m.value" :label="m.label" :value="m.value" />
      </el-select>
      <el-select v-model="merchantId" placeholder="商家" filterable style="width: 180px" @change="load">
        <el-option v-for="m in merchants" :key="m.id" :label="m.merchantName" :value="m.id" />
      </el-select>
      <el-button type="primary" @click="load">加载</el-button>
      <el-button type="warning" @click="printLabels">打印全部</el-button>
      <el-button @click="exportHtml">导出 HTML</el-button>
    </div>
    <p v-if="groups.length" class="meta">
      共 {{ groups.length }} 张标签 · 打印尺寸 {{ printConfig.widthMm }}mm × {{ printConfig.heightMm }}mm
    </p>

    <div class="preview" v-loading="loading">
      <div v-for="g in groups" :key="g.labelCode" class="label-card">
        <div class="code">{{ g.labelCode }}</div>
        <div v-for="(line, idx) in labelLines(g)" :key="idx" class="line">{{ line }}</div>
        <div v-if="g.remark" class="remark">备注：{{ g.remark }}</div>
      </div>
      <el-empty v-if="!loading && groups.length === 0" description="暂无标签数据" />
    </div>
  </div>
</template>

<script setup>
import { onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import { ElMessage } from 'element-plus';
import { adminApi, MEAL_OPTIONS, todayStr } from '../api/admin';

const route = useRoute();
const mealOptions = MEAL_OPTIONS;
const date = ref(route.query.date || todayStr());
const mealType = ref(route.query.mealType || 'lunch');
const merchantId = ref(route.query.merchantId || '');
const merchants = ref([]);
const groups = ref([]);
const loading = ref(false);
const printConfig = ref({ widthMm: 60, heightMm: 40, fontScale: 'standard' });

const FONT_SCALE = { small: 0.85, standard: 1.0, large: 1.15 };

function dishJoin(items, compact) {
  return (items || [])
    .map((d) => (d.quantity <= 1 ? d.name : compact ? `${d.name}x${d.quantity}` : `${d.name} x${d.quantity}`))
    .join('、');
}

function labelLines(g) {
  const lines = [`${g.employeeName}｜${g.department || '—'}`];
  if (g.packages?.length) {
    lines.push(`套餐：${g.packages.map((p) => `${p.name} x${p.quantity}`).join('、')}`);
  }
  if (g.meats?.length) {
    lines.push(`荤菜：${g.meats.map((m) => `${m.name} x${m.quantity}`).join('、')}`);
  }
  if (g.vegetables?.length) {
    lines.push(`素菜：${g.vegetables.map((v) => `${v.name} x${v.quantity}`).join('、')}`);
  }
  if (g.extras?.length) {
    lines.push(`加菜：${g.extras.map((e) => `${e.name} x${e.quantity}`).join('、')}`);
  }
  if (!g.packages?.length && !g.meats?.length && !g.vegetables?.length && g.items?.length) {
    g.items.forEach((i) => lines.push(`${i.dishName} x${i.quantity}`));
  }
  return lines;
}

function printLines(g) {
  const { widthMm, heightMm } = printConfig.value;
  const compact = widthMm <= 45 || heightMm <= 35;
  const lines = compact
    ? [`${g.labelCode} ${g.employeeName}`]
    : [g.labelCode, g.employeeName];
  if (g.packages?.length) {
    const text = dishJoin(g.packages, compact);
    lines.push(compact ? text : `套餐：${text}`);
  }
  if (g.meats?.length) {
    const text = dishJoin(g.meats, compact);
    lines.push(compact ? `荤：${text}` : `荤菜：${text}`);
  }
  if (g.vegetables?.length) {
    const text = dishJoin(g.vegetables, compact);
    lines.push(compact ? `素：${text}` : `素菜：${text}`);
  }
  if (g.extras?.length) {
    const text = dishJoin(g.extras, compact);
    lines.push(compact ? `加：${text}` : `加菜：${text}`);
  }
  if ((g.remark || '').trim()) {
    lines.push(`备注：${g.remark.trim()}`);
  }
  return lines;
}

function esc(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function printLabelPageHtml(g) {
  const { widthMm, heightMm } = printConfig.value;
  const compact = widthMm <= 45 || heightMm <= 35;
  const lines = printLines(g);
  if (compact) {
    const header = lines[0] || g.labelCode;
    const rest = lines.slice(1);
    const parts = header.split(' ');
    const code = parts[0] || g.labelCode;
    const name = parts.slice(1).join(' ') || g.employeeName;
    const body = rest.map((l) => `<div class="label-line">${esc(l)}</div>`).join('');
    return `<div class="label-page"><div class="label-header"><span class="label-code">${esc(code)}</span><span class="label-name">${esc(name)}</span></div>${body}</div>`;
  }
  const code = lines[0] ? `<div class="label-code">${esc(lines[0])}</div>` : '';
  const name = lines[1] ? `<div class="label-name">${esc(lines[1])}</div>` : '';
  const body = lines.slice(2).map((l) => `<div class="label-line">${esc(l)}</div>`).join('');
  return `<div class="label-page">${code}${name}${body}</div>`;
}

function printCss() {
  const { widthMm, heightMm, fontScale } = printConfig.value;
  const scale = FONT_SCALE[fontScale] || 1;
  const compact = widthMm <= 45 || heightMm <= 35;
  const codePx = ((compact ? 10 : 12) * scale).toFixed(1);
  const namePx = ((compact ? 10 : 13) * scale).toFixed(1);
  const linePx = ((compact ? 8 : 10) * scale).toFixed(1);
  const pad = compact ? '2mm' : '3mm';
  return `
@page { size: ${widthMm}mm ${heightMm}mm; margin: 0; }
html, body { margin: 0; padding: 0; background: #fff; }
.label-page {
  width: ${widthMm}mm; height: ${heightMm}mm; box-sizing: border-box; padding: ${pad};
  page-break-after: always; break-after: page; overflow: hidden; background: #fff;
  font-family: "Microsoft YaHei", sans-serif; color: #111;
}
.label-page:last-child { page-break-after: auto; break-after: auto; }
.label-header { display: flex; align-items: baseline; gap: 2mm; margin-bottom: 1mm; }
.label-code { font-size: ${codePx}px; font-weight: 700; color: #FF7A00; }
.label-name { font-size: ${namePx}px; font-weight: 700; line-height: 1.2; }
.label-line { font-size: ${linePx}px; line-height: 1.25; }
`;
}

async function loadConfig() {
  try {
    const res = await adminApi.getSystemConfig();
    printConfig.value = {
      widthMm: res.data.appSettings?.labelPrintWidthMm ?? 60,
      heightMm: 40,
      fontScale: 'standard',
    };
  } catch {
    /* ignore */
  }
}

async function loadMerchants() {
  const res = await adminApi.listMerchants();
  merchants.value = res.data || [];
  if (!merchantId.value && merchants.value.length) {
    merchantId.value = merchants.value[0].id;
  }
}

async function load() {
  if (!merchantId.value) return;
  loading.value = true;
  try {
    const res = await adminApi.listLabels({ date: date.value, mealType: mealType.value, merchantId: merchantId.value });
    groups.value = res.data || [];
  } catch (e) {
    ElMessage.error(e.message || '加载失败');
  } finally {
    loading.value = false;
  }
}

function printLabels() {
  if (!groups.value.length) {
    ElMessage.warning('暂无标签');
    return;
  }
  const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><style>${printCss()}</style></head><body>${groups.value.map(printLabelPageHtml).join('')}</body></html>`;
  const w = window.open('', '_blank');
  w.document.write(html);
  w.document.close();
  w.focus();
  w.print();
}

async function exportHtml() {
  try {
    await adminApi.exportLabelsHtml({
      date: date.value,
      mealType: mealType.value,
      merchantId: merchantId.value,
      widthMm: printConfig.value.widthMm,
      heightMm: printConfig.value.heightMm,
      fontScale: printConfig.value.fontScale,
    });
    ElMessage.success('已导出');
  } catch (e) {
    ElMessage.error(e.message || '导出失败');
  }
}

onMounted(async () => {
  await loadConfig();
  await loadMerchants();
  await load();
});
</script>

<style scoped>
.toolbar {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  margin-bottom: 8px;
}
.meta {
  font-size: 13px;
  color: #666;
  margin: 0 0 16px;
}
.preview {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
}
.label-card {
  border: 1px solid #ddd;
  border-radius: 6px;
  padding: 10px 12px;
  width: 220px;
  background: #fafafa;
}
.code {
  font-weight: 700;
  color: #2d8f47;
  margin-bottom: 4px;
}
.line {
  font-size: 13px;
  line-height: 1.45;
}
.remark {
  font-size: 12px;
  color: #666;
  margin-top: 6px;
}
</style>
