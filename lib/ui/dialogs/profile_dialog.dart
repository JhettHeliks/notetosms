import 'package:flutter/material.dart';
import 'package:notetosms/services/vault_service.dart';

class ProfileDialog extends StatefulWidget {
  const ProfileDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => const ProfileDialog(),
    );
  }

  @override
  State<ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<ProfileDialog> {
  final _nameController = TextEditingController();
  int _selectedColor = 0xFF1976D2;
  String _selectedIcon = 'person';
  bool _loading = true;
  bool _saving = false;

  final List<int> _colorOptions = const [
    0xFF1976D2, // Deep Ocean Blue
    0xFF388E3C, // Emerald Green
    0xFFF57C00, // Sunset Amber
    0xFF7B1FA2, // Obsidian Purple
    0xFFD32F2F, // Crimson Red
    0xFF00796B, // Teal Slate
    0xFFE91E63, // Neon Pink
    0xFF546E7A, // Steel Gray
  ];

  final List<Map<String, dynamic>> _iconOptions = const [
    {'name': 'person', 'icon': Icons.person_rounded},
    {'name': 'sentiment', 'icon': Icons.sentiment_satisfied_alt_rounded},
    {'name': 'flash', 'icon': Icons.flash_on_rounded},
    {'name': 'shield', 'icon': Icons.shield_outlined},
    {'name': 'rocket', 'icon': Icons.rocket_launch_rounded},
    {'name': 'star', 'icon': Icons.star_rounded},
    {'name': 'code', 'icon': Icons.code_rounded},
    {'name': 'coffee', 'icon': Icons.coffee_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await VaultService.instance.getUserProfile();
      if (mounted) {
        setState(() {
          _nameController.text = profile.displayName;
          _selectedColor = profile.avatarColor;
          _selectedIcon = profile.avatarIcon;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _nameController.text = 'NoteToSMS Device';
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);
    try {
      await VaultService.instance.saveUserProfile(
        displayName: name,
        avatarColor: _selectedColor,
        avatarIcon: _selectedIcon,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profile updated to "$name"'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving profile: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  IconData _getIconData(String name) {
    for (final opt in _iconOptions) {
      if (opt['name'] == name) {
        return opt['icon'] as IconData;
      }
    }
    return Icons.person_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activeColor = Color(_selectedColor);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      backgroundColor: colorScheme.surfaceContainerHigh,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: activeColor.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(_getIconData(_selectedIcon), color: activeColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'User Profile',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Network Handle & Avatar Accent',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: _loading
          ? const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  // Display Handle TextField
                  TextField(
                    controller: _nameController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Display Name / Handle',
                      hintText: 'e.g. Alice, Bob, Work Laptop',
                      prefixIcon: const Icon(Icons.badge_outlined),
                      filled: true,
                      fillColor: colorScheme.surfaceContainer,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: colorScheme.primary, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Avatar Color Picker
                  Text(
                    'Avatar Color Accent',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _colorOptions.map((c) {
                      final isSelected = _selectedColor == c;
                      final col = Color(c);
                      return GestureDetector(
                        onTap: () => setState(() => _selectedColor = c),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: col,
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(color: Colors.white, width: 3)
                                : Border.all(color: Colors.transparent, width: 3),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: col.withValues(alpha: 0.5),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, size: 18, color: Colors.white)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // Avatar Icon Picker
                  Text(
                    'Avatar Icon',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _iconOptions.map((opt) {
                      final name = opt['name'] as String;
                      final icon = opt['icon'] as IconData;
                      final isSelected = _selectedIcon == name;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedIcon = name),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? activeColor.withValues(alpha: 0.25)
                                : colorScheme.surfaceContainer,
                            borderRadius: BorderRadius.circular(12),
                            border: isSelected
                                ? Border.all(color: activeColor, width: 2)
                                : Border.all(color: Colors.transparent, width: 2),
                          ),
                          child: Icon(
                            icon,
                            size: 22,
                            color: isSelected ? activeColor : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _saveProfile,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check, size: 18),
          label: const Text('Save Handle'),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }
}
