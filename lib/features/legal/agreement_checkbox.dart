import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'legal_document_page.dart';
import 'legal_documents.dart';

/// 协议勾选行（登录页 / 入驻页通用）
///
/// 文案形如：
///   [ ] 我已阅读并同意《XXX》《YYY》《ZZZ》
///
/// 每个《...》都是可点击的链接，点击后跳转到对应静态协议页面。
class AgreementCheckboxRow extends StatelessWidget {
  /// 是否已勾选
  final bool agreed;

  /// 勾选状态变化回调
  final ValueChanged<bool> onChanged;

  /// 引导词，默认"我已阅读并同意"
  final String prefix;

  /// 需要展示的协议列表（按顺序排列）
  final List<LegalDocument> documents;

  /// 协议之间的连接符；为空时直接相邻
  final String separator;

  /// 是否居中
  final bool centered;

  const AgreementCheckboxRow({
    super.key,
    required this.agreed,
    required this.onChanged,
    required this.documents,
    this.prefix = '我已阅读并同意',
    this.separator = '',
    this.centered = true,
  });

  @override
  Widget build(BuildContext context) {
    final children = <InlineSpan>[];
    for (var i = 0; i < documents.length; i++) {
      if (i > 0 && separator.isNotEmpty) {
        children.add(TextSpan(
          text: separator,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ));
      }
      final doc = documents[i];
      children.add(
        TextSpan(
          text: '《${doc.title}》',
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 12,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => LegalDocumentPage.show(context, doc),
        ),
      );
    }

    final richText = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: prefix,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          ...children,
        ],
      ),
      textAlign: centered ? TextAlign.center : TextAlign.start,
    );

    final row = Row(
      mainAxisAlignment:
          centered ? MainAxisAlignment.center : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: GestureDetector(
            onTap: () => onChanged(!agreed),
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: agreed ? AppColors.primary : Colors.white,
                border: Border.all(
                  color: agreed
                      ? AppColors.primary
                      : AppColors.textTertiary,
                ),
                borderRadius: BorderRadius.circular(3),
              ),
              child: agreed
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(child: richText),
      ],
    );

    return row;
  }
}
