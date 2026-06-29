// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// 打开完整 HTML 文档并触发浏览器打印（专用标签打印页，不含 App UI）
void openPrintHtmlDocument(String fullHtml) {
  final blob = html.Blob([fullHtml], 'text/html');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.window.open(url, '_blank');
  html.Url.revokeObjectUrl(url);
}

/// @deprecated 使用 [openPrintHtmlDocument] 传入完整打印文档
void openPrintDocument(String htmlContent) {
  openPrintHtmlDocument(htmlContent);
}
