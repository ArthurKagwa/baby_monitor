import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/monitor_state.dart';
import '../theme.dart';
import 'logs_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<BabyMonitorState>();
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        children: [
          Text(
            'Settings',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          _SectionCard(
            title: 'Appearance',
            children: [
              const Text('Theme colour'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: ThemeType.values
                    .map(
                      (type) => _ThemeChip(
                        type: type,
                        selected: state.themeType == type,
                        onSelected: () =>
                            context.read<BabyMonitorState>().setTheme(type),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Notifications',
            children: [
              _SwitchTile(
                label: 'Cry alerts',
                value: state.cryAlertsEnabled,
                onChanged: context.read<BabyMonitorState>().toggleCryAlerts,
              ),
              const SizedBox(height: 12),
              _SwitchTile(
                label: 'Temperature alerts',
                value: state.temperatureAlertsEnabled,
                onChanged:
                    context.read<BabyMonitorState>().toggleTemperatureAlerts,
              ),
              const SizedBox(height: 16),
              _DropdownTile<AlertSound>(
                label: 'Alert sound',
                value: state.alertSound,
                items: AlertSound.values,
                itemLabel: _alertSoundLabel,
                onChanged: (sound) => context
                    .read<BabyMonitorState>()
                    .setAlertSound(sound ?? state.alertSound),
              ),
              const SizedBox(height: 16),
              _DropdownTile<_MuteOption>(
                label: 'Mute alerts for',
                value: _MuteOption.fromState(state),
                items: _MuteOption.values,
                itemLabel: (option) => option.label,
                onChanged: (option) {
                  final selected = option ?? _MuteOption.off;
                  context
                      .read<BabyMonitorState>()
                      .setMuteWindow(selected.duration);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Temperature',
            children: [
              _TemperatureRangeSlider(
                minValue: state.comfortMin,
                maxValue: state.comfortMax,
                onChanged: (min, max) {
                  context.read<BabyMonitorState>().setComfortTemperature(min, max);
                },
              ),
              const SizedBox(height: 16),
              _SwitchTile(
                label: 'Disable automatic fan',
                value: state.fanManualOverride,
                onChanged: context.read<BabyMonitorState>().setFanOverride,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Data',
            children: [
              _NavigationTile(
                label: 'Activity logs',
                icon: Icons.event_note_outlined,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const LogsScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'About',
            children: const [
              _SettingRow(label: 'App version', value: '0.1.0'),
              _SettingRow(label: 'Firmware', value: 'Unknown'),
            ],
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  String _alertSoundLabel(AlertSound sound) {
    switch (sound) {
      case AlertSound.softChime:
        return 'Soft chime';
      case AlertSound.standard:
        return 'Standard';
      case AlertSound.loud:
        return 'Loud';
    }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  const _ThemeChip({
    required this.type,
    required this.selected,
    required this.onSelected,
  });

  final ThemeType type;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final config = AppTheme.configFor(type);
    return GestureDetector(
      onTap: onSelected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? config.secondary : config.primary,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: config.secondary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              type.label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? Colors.white : config.onBackground,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium,
        ),
        Switch.adaptive(
          value: value,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _DropdownTile<T> extends StatelessWidget {
  const _DropdownTile({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        DropdownButton<T>(
          value: value,
          underline: const SizedBox.shrink(),
          borderRadius: BorderRadius.circular(16),
          onChanged: onChanged,
          items: items
              .map(
                (item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(itemLabel(item)),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _NavigationTile extends StatelessWidget {
  const _NavigationTile({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _MuteOption {
  off(null, 'Off'),
  five(Duration(minutes: 5), '5 min'),
  thirty(Duration(minutes: 30), '30 min');

  const _MuteOption(this.duration, this.label);

  final Duration? duration;
  final String label;

  static _MuteOption fromState(BabyMonitorState state) {
    if (!state.isMuted || state.mutedUntil == null) {
      return _MuteOption.off;
    }
    final remaining = state.mutedUntil!.difference(DateTime.now());
    if (remaining.inMinutes >= 20) {
      return _MuteOption.thirty;
    }
    if (remaining.inMinutes >= 3) {
      return _MuteOption.five;
    }
    return _MuteOption.off;
  }
}

class _TemperatureRangeSlider extends StatelessWidget {
  const _TemperatureRangeSlider({
    required this.minValue,
    required this.maxValue,
    required this.onChanged,
  });

  final double minValue;
  final double maxValue;
  final void Function(double min, double max) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Comfort range',
              style: theme.textTheme.bodyMedium,
            ),
            Text(
              '${minValue.toStringAsFixed(1)}°C - ${maxValue.toStringAsFixed(1)}°C',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildSlider(
          context,
          label: 'Min',
          value: minValue,
          min: 18.0,
          max: 24.0,
          onChanged: (value) => onChanged(value, maxValue),
        ),
        const SizedBox(height: 8),
        _buildSlider(
          context,
          label: 'Max',
          value: maxValue,
          min: 24.0,
          max: 30.0,
          onChanged: (value) => onChanged(minValue, value),
        ),
      ],
    );
  }

  Widget _buildSlider(
    BuildContext context, {
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(context);
    
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: ((max - min) * 2).toInt(),
            label: '${value.toStringAsFixed(1)}°C',
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 50,
          child: Text(
            '${value.toStringAsFixed(1)}°C',
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
