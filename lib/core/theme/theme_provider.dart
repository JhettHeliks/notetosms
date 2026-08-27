import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PalettePreset {
  final String name;
  final Color color;
  final String description;
  final IconData icon;

  const PalettePreset({
    required this.name,
    required this.color,
    required this.description,
    required this.icon,
  });
}

class ThemeSettings {
  final bool useDynamicColor;
  final Color customSeedColor;
  final ThemeMode themeMode;

  const ThemeSettings({
    required this.useDynamicColor,
    required this.customSeedColor,
    required this.themeMode,
  });

  ThemeSettings copyWith({
    bool? useDynamicColor,
    Color? customSeedColor,
    ThemeMode? themeMode,
  }) {
    return ThemeSettings(
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
      customSeedColor: customSeedColor ?? this.customSeedColor,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

class ThemeProvider extends ChangeNotifier {
  static const List<PalettePreset> presets = [
    PalettePreset(
      name: 'Deep Ocean',
      color: Color(0xFF1A73E8),
      description: 'Classic electric blue',
      icon: Icons.water_drop_rounded,
    ),
    PalettePreset(
      name: 'Emerald',
      color: Color(0xFF059669),
      description: 'Vibrant encrypted green',
      icon: Icons.eco_rounded,
    ),
    PalettePreset(
      name: 'Sunset Amber',
      color: Color(0xFFF59E0B),
      description: 'Warm glowing amber',
      icon: Icons.wb_sunny_rounded,
    ),
    PalettePreset(
      name: 'Obsidian Violet',
      color: Color(0xFF8B5CF6),
      description: 'Sleek cyber purple',
      icon: Icons.auto_awesome_rounded,
    ),
    PalettePreset(
      name: 'Crimson',
      color: Color(0xFFEF4444),
      description: 'Bold expressive red',
      icon: Icons.local_fire_department_rounded,
    ),
  ];

  static const String _prefDynamicColor = 'theme_use_dynamic_color';
  static const String _prefSeedColor = 'theme_custom_seed_color';
  static const String _prefThemeMode = 'theme_mode_index';

  ThemeSettings _settings = const ThemeSettings(
    useDynamicColor: true,
    customSeedColor: Color(0xFF1A73E8),
    themeMode: ThemeMode.dark,
  );

  ThemeSettings get settings => _settings;
  bool get useDynamicColor => _settings.useDynamicColor;
  Color get customSeedColor => _settings.customSeedColor;
  ThemeMode get themeMode => _settings.themeMode;

  ThemeProvider() {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dynamicColor = prefs.getBool(_prefDynamicColor) ?? true;
      final seedInt = prefs.getInt(_prefSeedColor) ?? 0xFF1A73E8;
      final modeIndex = prefs.getInt(_prefThemeMode) ?? ThemeMode.dark.index;

      _settings = ThemeSettings(
        useDynamicColor: dynamicColor,
        customSeedColor: Color(seedInt),
        themeMode: ThemeMode.values[modeIndex.clamp(0, ThemeMode.values.length - 1)],
      );
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setUseDynamicColor(bool value) async {
    if (_settings.useDynamicColor == value) return;
    _settings = _settings.copyWith(useDynamicColor: value);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefDynamicColor, value);
    } catch (_) {}
  }

  Future<void> setCustomSeedColor(Color color) async {
    if (_settings.customSeedColor.toARGB32() == color.toARGB32() && !_settings.useDynamicColor) return;
    // When a custom swatch is clicked, automatically switch off dynamic color so user sees change immediately
    _settings = _settings.copyWith(
      customSeedColor: color,
      useDynamicColor: false,
    );
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefSeedColor, color.toARGB32());
      await prefs.setBool(_prefDynamicColor, false);
    } catch (_) {}
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_settings.themeMode == mode) return;
    _settings = _settings.copyWith(themeMode: mode);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefThemeMode, mode.index);
    } catch (_) {}
  }
}
