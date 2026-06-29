<template>
  <div class="img-row">
    <span class="img-label">{{ label }}：</span>
    <el-image
      v-if="showImage"
      class="qual-thumb"
      :src="src"
      :preview-src-list="previewList"
      :initial-index="0"
      fit="cover"
      preview-teleported
      title="点击查看大图"
    >
      <template #error>
        <div class="img-placeholder error">图片加载失败</div>
      </template>
    </el-image>
    <span v-else class="img-placeholder">未上传</span>
  </div>
</template>

<script setup>
import { computed } from 'vue';
import { fullImageUrl, isUploadImageUrl } from '../api/admin';

const props = defineProps({
  label: { type: String, required: true },
  url: { type: String, default: '' },
});

const showImage = computed(() => isUploadImageUrl(props.url));
const src = computed(() => fullImageUrl(props.url));
const previewList = computed(() => (src.value ? [src.value] : []));
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
  min-width: 112px;
  line-height: 96px;
}
.img-placeholder {
  line-height: 96px;
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
