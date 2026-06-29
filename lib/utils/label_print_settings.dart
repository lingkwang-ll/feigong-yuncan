import 'package:shared_preferences/shared_preferences.dart';

/// 标签字体档位
enum LabelFontScale {
  small('小', 0.85),
  standard('标准', 1.0),
  large('大', 1.15);

  final String label;
  final double factor;
  const LabelFontScale(this.label, this.factor);

  static LabelFontScale fromKey(String? key) {
    return LabelFontScale.values.firstWhere(
      (e) => e.name == key,
      orElse: () => LabelFontScale.standard,
    );
  }
}

/// 商家端标签打印设置（本地 SharedPreferences）
class LabelPrintSettings {
  LabelPrintSettings._({
    required this.labelWidthMm,
    required this.labelHeightMm,
    required this.fontScale,
    required this.showPackage,
    required this.showMeat,
    required this.showVegetable,
    required this.showExtra,
    required this.showRemark,
    required this.labelCopies,
  });

  double labelWidthMm;
  double labelHeightMm;
  LabelFontScale fontScale;
  bool showPackage;
  bool showMeat;
  bool showVegetable;
  bool showExtra;
  bool showRemark;
  int labelCopies;

  static const defaultWidthMm = 60.0;
  static const defaultHeightMm = 40.0;

  static const widthPresets = [40.0, 50.0, 60.0, 70.0, 80.0];
  static const heightPresets = [30.0, 40.0, 50.0, 60.0];

  static const _kWidth = 'labelPrintWidthMm';
  static const _kHeight = 'labelPrintHeightMm';
  static const _kFontScale = 'labelPrintFontScale';
  static const _kShowPackage = 'labelPrintShowPackage';
  static const _kShowMeat = 'labelPrintShowMeat';
  static const _kShowVegetable = 'labelPrintShowVegetable';
  static const _kShowExtra = 'labelPrintShowExtra';
  static const _kShowRemark = 'labelPrintShowRemark';
  static const _kCopies = 'labelPrintCopies';

  static LabelPrintSettings _cached = LabelPrintSettings.defaults();
  static bool _loaded = false;

  factory LabelPrintSettings.defaults() => LabelPrintSettings._(
        labelWidthMm: defaultWidthMm,
        labelHeightMm: defaultHeightMm,
        fontScale: LabelFontScale.standard,
        showPackage: true,
        showMeat: true,
        showVegetable: true,
        showExtra: true,
        showRemark: true,
        labelCopies: 1,
      );

  static LabelPrintSettings get current {
    if (!_loaded) {
      return LabelPrintSettings.defaults();
    }
    return _cached;
  }

  String get sizeLabel =>
      '${labelWidthMm.toStringAsFixed(labelWidthMm == labelWidthMm.roundToDouble() ? 0 : 1)}mm × ${labelHeightMm.toStringAsFixed(labelHeightMm == labelHeightMm.roundToDouble() ? 0 : 1)}mm';

  bool get isCompact => labelWidthMm <= 45 || labelHeightMm <= 35;

  static Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _cached = LabelPrintSettings._(
      labelWidthMm: prefs.getDouble(_kWidth) ?? defaultWidthMm,
      labelHeightMm: prefs.getDouble(_kHeight) ?? defaultHeightMm,
      fontScale: LabelFontScale.fromKey(prefs.getString(_kFontScale)),
      showPackage: prefs.getBool(_kShowPackage) ?? true,
      showMeat: prefs.getBool(_kShowMeat) ?? true,
      showVegetable: prefs.getBool(_kShowVegetable) ?? true,
      showExtra: prefs.getBool(_kShowExtra) ?? true,
      showRemark: prefs.getBool(_kShowRemark) ?? true,
      labelCopies: prefs.getInt(_kCopies) ?? 1,
    );
    _loaded = true;
  }

  static Future<void> save(LabelPrintSettings settings) async {
    _cached = settings;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kWidth, settings.labelWidthMm);
    await prefs.setDouble(_kHeight, settings.labelHeightMm);
    await prefs.setString(_kFontScale, settings.fontScale.name);
    await prefs.setBool(_kShowPackage, settings.showPackage);
    await prefs.setBool(_kShowMeat, settings.showMeat);
    await prefs.setBool(_kShowVegetable, settings.showVegetable);
    await prefs.setBool(_kShowExtra, settings.showExtra);
    await prefs.setBool(_kShowRemark, settings.showRemark);
    await prefs.setInt(_kCopies, settings.labelCopies);
  }

  Future<void> persist() => LabelPrintSettings.save(this);

  LabelPrintSettings copy() => LabelPrintSettings._(
        labelWidthMm: labelWidthMm,
        labelHeightMm: labelHeightMm,
        fontScale: fontScale,
        showPackage: showPackage,
        showMeat: showMeat,
        showVegetable: showVegetable,
        showExtra: showExtra,
        showRemark: showRemark,
        labelCopies: labelCopies,
      );

  Future<void> resetToDefaults() async {
    final d = LabelPrintSettings.defaults();
    labelWidthMm = d.labelWidthMm;
    labelHeightMm = d.labelHeightMm;
    fontScale = d.fontScale;
    showPackage = d.showPackage;
    showMeat = d.showMeat;
    showVegetable = d.showVegetable;
    showExtra = d.showExtra;
    showRemark = d.showRemark;
    labelCopies = d.labelCopies;
    await persist();
  }
}
