import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:notetosms/core/theme/theme_provider.dart';
import 'package:notetosms/ui/widgets/motion/bouncy_pressable.dart';
import 'package:notetosms/ui/widgets/motion/fade_slide_transition.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeProvider = context.watch<ThemeProvider>();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'Appearance & Themes',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: BouncyPressable(
          onTap: () => Navigator.pop(context),
          child: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        physics: const BouncingScrollPhysics(),
        children: [
          // 1. Theme Mode Section
          FadeSlideTransition(
            child: _buildSectionCard(
              context: context,
              title: 'Theme Mode',
              icon: Icons.brightness_6_rounded,
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.system,
                    label: Text('System'),
                    icon: Icon(Icons.brightness_auto_rounded),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.light,
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode_rounded),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.dark,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode_rounded),
                  ),
                ],
                selected: {themeProvider.themeMode},
                onSelectionChanged: (Set<ThemeMode> newSelection) {
                  themeProvider.setThemeMode(newSelection.first);
                },
                style: ButtonStyle(
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // 2. Material You Dynamic Color Toggle
          FadeSlideTransition(
            delay: const Duration(milliseconds: 60),
            child: _buildSectionCard(
              context: context,
              title: 'Material You',
              icon: Icons.palette_outlined,
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Dynamic Wallpaper Color',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                subtitle: Text(
                  'Extract accents automatically from device wallpaper (Android 12+)',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                value: themeProvider.useDynamicColor,
                activeTrackColor: colorScheme.primary,
                onChanged: (bool value) {
                  themeProvider.setUseDynamicColor(value);
                },
              ),
            ),
          ),
          const SizedBox(height: 18),

          // 3. Custom Accent Palette Presets
          FadeSlideTransition(
            delay: const Duration(milliseconds: 120),
            child: _buildSectionCard(
              context: context,
              title: 'Accent Palette Presets',
              icon: Icons.color_lens_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selecting a preset applies custom vibrant accents and overrides wallpaper dynamic colors.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (final preset in ThemeProvider.presets) ...[
                    _buildPresetTile(
                      context: context,
                      preset: preset,
                      isSelected: !themeProvider.useDynamicColor &&
                          themeProvider.customSeedColor.toARGB32() == preset.color.toARGB32(),
                      onTap: () {
                        themeProvider.setCustomSeedColor(preset.color);
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // 4. Live Preview Banner
          FadeSlideTransition(
            delay: const Duration(milliseconds: 180),
            child: _buildSectionCard(
              context: context,
              title: 'Theme Preview',
              icon: Icons.remove_red_eye_outlined,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Mock outgoing note
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          'Encrypted note preview ✨',
                          style: TextStyle(
                            color: colorScheme.onPrimaryContainer,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Mock incoming note
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          'Synced securely across mesh peers 🛡️',
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildPresetTile({
    required BuildContext context,
    required PalettePreset preset,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return BouncyPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? preset.color.withValues(alpha: 0.16)
              : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? preset.color : colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: isSelected ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: preset.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: preset.color.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                isSelected ? Icons.check_rounded : preset.icon,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.name,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? preset.color : colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    preset.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.radio_button_checked_rounded, color: preset.color, size: 20)
            else
              Icon(Icons.radio_button_off_rounded, color: colorScheme.outlineVariant, size: 20),
          ],
        ),
      ),
    );
  }
}
