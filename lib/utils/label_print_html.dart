import 'meal_batch_aggregator.dart';
import 'label_print_settings.dart';

/// 生成适配小型标签打印机的 HTML 文档（每张标签独立分页）
class LabelPrintHtml {
  LabelPrintHtml._();

  static String escapeHtml(String raw) {
    return raw
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  static String _dishJoin(List<MealLabelDishLine> items, {required bool compact}) {
    return items
        .map((d) {
          if (d.quantity <= 1) return d.name;
          return compact ? '${d.name}x${d.quantity}' : '${d.name} x${d.quantity}';
        })
        .join('、');
  }

  static List<String> printLines(MealLabelGroup group, LabelPrintSettings settings) {
    final compact = settings.isCompact;
    final lines = <String>[];

    if (compact) {
      lines.add('${group.labelCode} ${group.employeeName}');
    } else {
      lines.add(group.labelCode);
      lines.add(group.employeeName);
    }

    if (settings.showPackage && group.packages.isNotEmpty) {
      final text = _dishJoin(group.packages, compact: compact);
      lines.add(compact ? text : '套餐：$text');
    }
    if (settings.showMeat && group.meats.isNotEmpty) {
      final text = _dishJoin(group.meats, compact: compact);
      lines.add(compact ? '荤：$text' : '荤菜：$text');
    }
    if (settings.showVegetable && group.vegetables.isNotEmpty) {
      final text = _dishJoin(group.vegetables, compact: compact);
      lines.add(compact ? '素：$text' : '素菜：$text');
    }
    if (settings.showExtra && group.extras.isNotEmpty) {
      final text = _dishJoin(group.extras, compact: compact);
      final suffix = group.extrasFollowOrder ? '（随单）' : '';
      lines.add(compact ? '加：$text$suffix' : '加菜：$text$suffix');
    }
    if (settings.showRemark && group.remark.trim().isNotEmpty) {
      lines.add(compact ? '备注：${group.remark.trim()}' : '备注：${group.remark.trim()}');
    }

    return lines;
  }

  static String _printCss(LabelPrintSettings settings) {
    final w = settings.labelWidthMm;
    final h = settings.labelHeightMm;
    final scale = settings.fontScale.factor;
    final compact = settings.isCompact;
    final codePx = ((compact ? 10.0 : 12.0) * scale).toStringAsFixed(1);
    final namePx = ((compact ? 10.0 : 13.0) * scale).toStringAsFixed(1);
    final linePx = ((compact ? 8.0 : 10.0) * scale).toStringAsFixed(1);
    final pad = compact ? '2mm' : '3mm';

    return '''
@page {
  size: ${w}mm ${h}mm;
  margin: 0;
}
html, body {
  margin: 0;
  padding: 0;
  background: #fff;
  -webkit-print-color-adjust: exact;
  print-color-adjust: exact;
}
.label-page {
  width: ${w}mm;
  height: ${h}mm;
  box-sizing: border-box;
  padding: $pad;
  page-break-after: always;
  break-after: page;
  overflow: hidden;
  background: #fff;
  font-family: "Microsoft YaHei", "PingFang SC", sans-serif;
  color: #111;
}
.label-page:last-child {
  page-break-after: auto;
  break-after: auto;
}
.label-header {
  display: flex;
  align-items: baseline;
  gap: 2mm;
  margin-bottom: 1mm;
}
.label-code {
  font-size: ${codePx}px;
  font-weight: 700;
  color: #FF7A00;
  flex-shrink: 0;
}
.label-name {
  font-size: ${namePx}px;
  font-weight: 700;
  line-height: 1.2;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.label-line {
  font-size: ${linePx}px;
  line-height: 1.25;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
@media print {
  html, body { margin: 0; padding: 0; background: #fff; }
}
''';
  }

  static String _labelPageHtml(MealLabelGroup group, LabelPrintSettings settings) {
    final lines = printLines(group, settings);
    final compact = settings.isCompact;
    final buf = StringBuffer();
    buf.writeln('<div class="label-page">');

    if (compact) {
      final header = lines.isNotEmpty ? lines.first : group.labelCode;
      final rest = lines.length > 1 ? lines.sublist(1) : <String>[];
      final parts = header.split(' ');
      final code = parts.isNotEmpty ? parts.first : group.labelCode;
      final name = parts.length > 1 ? parts.sublist(1).join(' ') : group.employeeName;
      buf.writeln('<div class="label-header">');
      buf.writeln('<span class="label-code">${escapeHtml(code)}</span>');
      buf.writeln('<span class="label-name">${escapeHtml(name)}</span>');
      buf.writeln('</div>');
      for (final line in rest) {
        buf.writeln('<div class="label-line">${escapeHtml(line)}</div>');
      }
    } else {
      if (lines.isNotEmpty) {
        buf.writeln('<div class="label-code">${escapeHtml(lines.first)}</div>');
      }
      if (lines.length > 1) {
        buf.writeln('<div class="label-name">${escapeHtml(lines[1])}</div>');
      }
      for (final line in lines.skip(2)) {
        buf.writeln('<div class="label-line">${escapeHtml(line)}</div>');
      }
    }

    buf.writeln('</div>');
    return buf.toString();
  }

  static String buildDocument(
    List<MealLabelGroup> groups,
    LabelPrintSettings settings,
  ) {
    final copies = settings.labelCopies.clamp(1, 2);
    final pages = StringBuffer();
    for (final group in groups) {
      for (var i = 0; i < copies; i++) {
        pages.write(_labelPageHtml(group, settings));
      }
    }

    return '''<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>非攻云餐 · 餐盒标签</title>
<style>${_printCss(settings)}</style></head>
<body>
$pages
<script>window.onload = function(){ window.print(); };</script>
</body></html>''';
  }
}
