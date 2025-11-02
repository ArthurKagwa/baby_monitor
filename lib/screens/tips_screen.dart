import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/monitor_state.dart';

class TipsScreen extends StatefulWidget {
  const TipsScreen({super.key});

  @override
  State<TipsScreen> createState() => _TipsScreenState();
}

class _TipsScreenState extends State<TipsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const List<Map<String, String>> _tips = [
    {
      'title': 'Safe sleep',
      'body':
          'Place baby on their back in a clear crib without loose bedding, pillows, or toys. Keep the room at a comfortable temperature.'
    },
    {
      'title': 'Feeding cues',
      'body':
          'Look for early feeding cues: lip smacking, rooting, hand-to-mouth — try to feed before crying begins.'
    },
    {
      'title': 'Soothing',
      'body':
          'Gentle rocking, swaddling (for young infants), white noise, and rhythmic pats can help calm a crying baby.'
    },
    {
      'title': 'Temperature',
      'body':
          'Aim for a comfortable room temperature and dress baby in one more layer than you would wear. Use the monitor to check room temp.'
    },
    {
      'title': 'Bonding',
      'body':
          'Skin-to-skin contact and eye contact during quiet alert times supports attachment and soothes your baby.'
    },
    {
      'title': 'When to call',
      'body':
          'If your baby has difficulty breathing, bluish lips, a fever in young infants, or a prolonged inconsolable cry, seek medical help.'
    },
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<BabyMonitorState>();
    
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Care tips',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Practical tips for everyday care.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                height: 110,
                child: _AnimatedBaby(controllerProvider: () => _controller),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Offline status card with last readings
          if (state.connectionStatus != ConnectionStatus.connected && state.lastConnectedTime != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.cloud_off, size: 20, color: theme.colorScheme.onSurface.withOpacity(0.7)),
                          const SizedBox(width: 8),
                          Text(
                            'Device Offline',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Last connected: ${_formatLastConnected(state.lastConnectedTime!)}',
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (state.lastDeviceName != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Device: ${state.lastDeviceName}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ],
                      if (state.tempHistory.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Divider(),
                        const SizedBox(height: 8),
                        Text(
                          'Last readings available in Logs tab',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

          // Generic tips list
          ..._tips.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t['title']!,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t['body']!,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              )),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Helpful reminders',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('- Check the room temperature regularly.',
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text('- Keep monitoring volume at a comfortable level.',
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text('- Keep the crib free from loose items for sleep safety.',
                      style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ),
          const SizedBox(height: 64),
        ],
      ),
    );
  }

  String _formatLastConnected(DateTime lastConnected) {
    final now = DateTime.now();
    final difference = now.difference(lastConnected);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hr ago';
    } else {
      return '${difference.inDays} days ago';
    }
  }
}

class _AnimatedBaby extends StatelessWidget {
  const _AnimatedBaby({Key? key, required this.controllerProvider}) : super(key: key);

  final AnimationController Function() controllerProvider;

  @override
  Widget build(BuildContext context) {
    final controller = controllerProvider();
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        // generate values based on controller value
        final t = controller.value;
        final double bob = math.sin(t * math.pi * 2) * 6; // vertical bob
        final double rotate = math.sin(t * math.pi * 2) * 0.08; // small rotation

        return Stack(
          alignment: Alignment.center,
          children: [
            // small balloon floating to the top-left
            Positioned(
              left: 6,
              top: 8 - bob / 3,
                child: Transform.rotate(
                angle: rotate * 2,
                child: Icon(Icons.celebration, size: 22, color: Colors.pink[200]),
              ),
            ),
            Transform.translate(
              offset: Offset(0, -bob),
              child: Transform.rotate(
                angle: rotate,
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withAlpha((0.12 * 255).round()),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      Icons.child_care,
                      size: 44,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
            // tiny pacifier rotation near the baby
            Positioned(
              right: 6,
              bottom: 6 + bob / 4,
              child: Transform.rotate(
                angle: rotate * -3,
                child: Icon(Icons.circle, size: 12, color: Colors.orange[200]),
              ),
            ),
          ],
        );
      },
    );
  }
}
