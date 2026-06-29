<template>
  <div class="img-row">
    <span class="img-label">
      {{ label }}：
      <span v-if="resolvedList.length" class="img-count">已上传 {{ resolvedList.length }} 张</span>
    </span>
    <div v-if="resolvedList.length" class="img-list">
      <el-image
        v-for="(src, i) in resolvedList"
        :key="src + '_' + i"
        class="qual-thumb"
        :src="src"
        :preview-src-list="resolvedList"
        :initial-index="i"
        fit="cover"
        preview-teleported
        title="点击查看大图"
      >
        <template #error>
          <div class="img-placeholder error">加载失败</div>
        </template>
      </el-image>
    </div>
    <span v-else class="img-placeholder">未填写</span>
  </div>
</template>

<script setup>
import { computed } from 'vue';
import { fullImageUrl, isUploadImageUrl } from '../api/admin';

const props = defineProps({
  label: { type: String, required: true },
  /**
   * 多图列表（向后兼容旧单图字段）。若传入空数组，会显示"未填写"。
   * 调用方需自己把旧单图字段塞入数组首位（mapper 已做了这件事）。
   */
  urls: { type: Array, default: () => [] },
  /**
   * 兜底单图字段：当 urls 为空时，若该字段是合法图片 URL，
   * 仍渲染成一张图，避免历史商家看不到图。
   */
  fallback: { type: String, default: '' },
});

const resolvedList = computed(() => {
  const list = (props.urls || [])
    .map((u) => (u == null ? '' : String(u).trim()))
    .filter((u) => isUploadImageUrl(u))
    .map((u) => fullImageUrl(u));
  if (list.length) return list;
  const fb = String(props.fallback || '').trim();
  if (isUploadImageUrl(fb)) return [fullImageUrl(fb)];
  return [];
});
</script>

<style scoped>
.img-row {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  margin: 10px 0;
  font-size: 13px;
  color: #555;
}
.img-label {
  flex-shrink: 0;
  min-width: 132px;
  padding-top: 4px;
  line-height: 1.6;
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.img-count {
  color: #909399;
  font-size: 12px;
}
.img-list {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
.img-placeholder {
  line-height: 32px;
  color: #909399;
  font-size: 13px;
}
.img-placeholder.error {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 96px;
  height: 96px;
  line-height: 1.4;
  padding: 8px;
  text-align: center;
  border: 1px dashed #f56c6c;
  border-radius: 8px;
  color: #f56c6c;
  font-size: 12px;
}
.qual-thumb {
  width: 96px;
  height: 96px;
  border-radius: 8px;
  border: 1px solid #e4e7ed;
  cursor: zoom-in;
  flex-shrink: 0;
}
.qual-thumb :deep(.el-image__inner) {
  width: 96px;
  height: 96px;
  border-radius: 8px;
}
</style>
