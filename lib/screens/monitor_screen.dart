import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:developer' as developer;

import '../state/monitor_state.dart';
import '../widgets/temperature_gauge.dart';

class MonitorScreen extends StatelessWidget {
  const MonitorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<BabyMonitorState>();
    final bool offline = state.connectionStatus != ConnectionStatus.connected;
    final temperature = state.temperature;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        children: [
          ConnectionBanner(
            status: state.connectionStatus,
            label: state.connectionLabel,
            onTap: () => _showConnectionSheet(context),
          ),
          const SizedBox(height: 20),
          if (state.isMuted)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: _MutedChip(remaining: state.muteRemaining),
            ),
          if (offline && state.lastConnectedTime != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: _OfflineInfoCard(
                lastConnectedTime: state.lastConnectedTime!,
                lastDeviceName: state.lastDeviceName,
              ),
            ),
          TemperatureCard(
            temperature: temperature,
            state: state,
            showLastReading: offline && state.tempHistory.isNotEmpty,
          ),
          if (!offline) ...[
            const SizedBox(height: 16),
            CryCard(
              crying: state.crying,
              recentlyCrying: state.recentlyCrying,
              sinceLastCry: state.timeSinceLastCry,
            ),
            const SizedBox(height: 16),
            FanCard(
              fanRunning: state.fanRunning,
            ),
          ],
          const SizedBox(height: 64),
        ],
      ),
    );
  }

  void _showConnectionSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        final state = context.read<BabyMonitorState>();
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Connection',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                state.connectionLabel,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  state.requestReconnect();
                },
                icon: const Icon(Icons.bluetooth_searching),
                label: const Text('Reconnect / Scan'),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.close),
                label: const Text('Close'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TempSparkline extends StatelessWidget {
  const _TempSparkline({required this.samples, required this.color, this.minValue, this.maxValue});

  final List<TempSample> samples;
  final Color color;
  final double? minValue;
  final double? maxValue;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparklinePainter(samples: samples, color: color, minValue: minValue, maxValue: maxValue),
      size: Size.infinite,
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.samples, required this.color, this.minValue, this.maxValue});

  final List<TempSample> samples;
  final Color color;
  final double? minValue;
  final double? maxValue;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    if (samples.isEmpty) return;

    double minT = samples.map((s) => s.temperature).reduce((a, b) => a < b ? a : b);
    double maxT = samples.map((s) => s.temperature).reduce((a, b) => a > b ? a : b);
    if (minValue != null) minT = math.min(minT, minValue!);
    if (maxValue != null) maxT = math.max(maxT, maxValue!);
    if ((maxT - minT).abs() < 0.1) maxT = minT + 0.1;

    final path = Path();
    final List<Path> fillPaths = [];
    Path? currentFillPath;
    bool pathStarted = false;
    double? segmentStartX;

    for (int i = 0; i < samples.length; i++) {
      final s = samples[i];
      final x = (i / (samples.length - 1)).clamp(0.0, 1.0) * size.width;
      final y = size.height - ((s.temperature - minT) / (maxT - minT)).clamp(0.0, 1.0) * size.height;
      
      // Break the line if temperature is zero or very close to zero
      if (s.temperature.abs() < 0.01) {
        // Close current fill path if exists
        if (currentFillPath != null && segmentStartX != null) {
          final lastValidI = i - 1;
          if (lastValidI >= 0) {
            final lastX = (lastValidI / (samples.length - 1)).clamp(0.0, 1.0) * size.width;
            currentFillPath.lineTo(lastX, size.height);
            currentFillPath.lineTo(segmentStartX, size.height);
            currentFillPath.close();
            fillPaths.add(currentFillPath);
          }
          currentFillPath = null;
          segmentStartX = null;
        }
        pathStarted = false;
        continue;
      }
      
      if (!pathStarted) {
        path.moveTo(x, y);
        pathStarted = true;
        // Start new fill path
        currentFillPath = Path();
        segmentStartX = x;
        currentFillPath.moveTo(x, size.height);
        currentFillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        currentFillPath?.lineTo(x, y);
      }
    }
    
    // Close the last fill path if it exists
    if (currentFillPath != null && segmentStartX != null && samples.isNotEmpty) {
      final lastValidIndex = samples.length - 1;
      final lastX = (lastValidIndex / (samples.length - 1)).clamp(0.0, 1.0) * size.width;
      currentFillPath.lineTo(lastX, size.height);
      currentFillPath.lineTo(segmentStartX, size.height);
      currentFillPath.close();
      fillPaths.add(currentFillPath);
    }

  // Draw extreme zones (red shading) under the trend line if min/max values are provided
    if (minValue != null && maxValue != null) {
      final maxY = size.height - ((maxValue! - minT) / (maxT - minT)).clamp(0.0, 1.0) * size.height;
      final minY = size.height - ((minValue! - minT) / (maxT - minT)).clamp(0.0, 1.0) * size.height;

      // Create paths for extreme zones under the trend line
      final Path highZonePath = Path();
      final Path lowZonePath = Path();
      
      for (int i = 0; i < samples.length; i++) {
        final s = samples[i];
        
        // Skip zero values
        if (s.temperature.abs() < 0.01) continue;
        
        final x = (i / (samples.length - 1)).clamp(0.0, 1.0) * size.width;
        final y = size.height - ((s.temperature - minT) / (maxT - minT)).clamp(0.0, 1.0) * size.height;
        
        // High zone: if temp is above maxValue, shade from trend line to maxY
        if (s.temperature > maxValue!) {
          if (i == 0 || samples[i - 1].temperature <= maxValue!) {
            highZonePath.moveTo(x, maxY);
          }
          highZonePath.lineTo(x, y);
        } else if (i > 0 && samples[i - 1].temperature > maxValue!) {
          // Close the high zone path
          highZonePath.lineTo(x, maxY);
          highZonePath.close();
        }
        
        // Low zone: if temp is below minValue, shade from trend line to minY
        if (s.temperature < minValue!) {
          if (i == 0 || samples[i - 1].temperature >= minValue!) {
            lowZonePath.moveTo(x, minY);
          }
          lowZonePath.lineTo(x, y);
        } else if (i > 0 && samples[i - 1].temperature < minValue!) {
          // Close the low zone path
          lowZonePath.lineTo(x, minY);
          lowZonePath.close();
        }
      }
      
      // Draw the extreme zone shading
      final extremePaint = Paint()
        ..color = const Color(0xFFE74C3C).withAlpha((0.2 * 255).round())
        ..style = PaintingStyle.fill;
      
      canvas.drawPath(highZonePath, extremePaint);
      canvas.drawPath(lowZonePath, extremePaint);
    }

  // fill under curve (normal gradient)
  final fillPaint = Paint()..color = color.withAlpha((0.12 * 255).round())..style = PaintingStyle.fill;
  
  // Draw all fill path segments
  for (final fillPath in fillPaths) {
    canvas.drawPath(fillPath, fillPaint);
  }

    // line
    canvas.drawPath(path, paint);

    // last point - only draw if the last sample is not zero
    final last = samples.last;
    if (last.temperature.abs() >= 0.01) {
      final lastX = size.width;
      final lastY = size.height - ((last.temperature - minT) / (maxT - minT)).clamp(0.0, 1.0) * size.height;
      final dotPaint = Paint()..color = color;
      canvas.drawCircle(Offset(lastX, lastY), 3.0, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.samples != samples || oldDelegate.color != color || oldDelegate.minValue != minValue || oldDelegate.maxValue != maxValue;
  }
}

class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({
    super.key,
    required this.status,
    required this.label,
    required this.onTap,
  });

  final ConnectionStatus status;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context, status);

    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(BuildContext context, ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return const Color(0xFF2ECC71);
      case ConnectionStatus.reconnecting:
        return const Color(0xFFF39C12);
      case ConnectionStatus.disconnected:
        return const Color(0xFFE74C3C);
    }
  }
}

class TemperatureCard extends StatefulWidget {
  const TemperatureCard({
    super.key,
    required this.temperature,
    required this.state,
    this.showLastReading = false,
  });

  final double? temperature;
  final BabyMonitorState state;
  final bool showLastReading;

  @override
  State<TemperatureCard> createState() => _TemperatureCardState();
}

class _TemperatureCardState extends State<TemperatureCard> {
  @override
  Widget build(BuildContext context) {
    developer.log('TemperatureCard.build - temp: ${widget.temperature}, alert: ${widget.state.tempAlert}', 
        name: 'TemperatureCard');
    final theme = Theme.of(context);
    final labelColor = theme.colorScheme.onSurfaceVariant;
    final bool offline = widget.temperature == null;
    final status = widget.state.tempAlert;
    
    // For offline state with history, show the last reading
    final double? displayTemp = offline && widget.showLastReading && widget.state.tempHistory.isNotEmpty
        ? widget.state.tempHistory.last.temperature
        : widget.temperature;
    
    final statusLabel = offline
        ? (widget.showLastReading ? 'Last reading' : 'Offline')
        : switch (status) {
            TempAlertStatus.ok => 'Comfort',
            TempAlertStatus.low => 'Too cold',
            TempAlertStatus.high => 'Too hot',
          };
    final statusColor = offline
        ? theme.colorScheme.onSurfaceVariant
        : switch (status) {
            TempAlertStatus.ok => theme.colorScheme.secondary,
            TempAlertStatus.low => const Color(0xFF2D8CFF),
            TempAlertStatus.high => const Color(0xFFD64545),
          };

    final statusChipBackground = offline
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.08)
        : statusColor.withValues(alpha: 0.1);

    final statusDotColor =
        offline ? statusColor.withValues(alpha: 0.5) : statusColor;

    final headlineTemperature = displayTemp == null
        ? '--.- °C'
        : '${displayTemp.toStringAsFixed(1)} °C';

    final subtitle = 'Comfort ${widget.state.comfortMin.toStringAsFixed(0)}–${widget.state.comfortMax.toStringAsFixed(0)} °C';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Room temperature',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        headlineTemperature,
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontSize: 44,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                        const SizedBox(height: 8),
                        // Sparkline showing recent temperature trend
                        if (widget.state.tempHistory.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6, bottom: 6),
                            child: SizedBox(
                              height: 48,
                              child: _TempSparkline(
                                samples: widget.state.tempHistory,
                                color: theme.colorScheme.primary,
                                minValue: widget.state.comfortMin,
                                maxValue: widget.state.comfortMax,
                              ),
                            ),
                          ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: labelColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TemperatureGauge(
              temperature: displayTemp,
              minValue: 18,
              maxValue: 32,
              alertStatus: status,
              dimmed: false, // Don't grey out the gauge anymore
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: statusChipBackground,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: statusDotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    statusLabel,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CryCard extends StatefulWidget {
  const CryCard({
    super.key,
    required this.crying,
    required this.recentlyCrying,
    required this.sinceLastCry,
  });

  final bool crying;
  final bool recentlyCrying;
  final Duration? sinceLastCry;

  @override
  State<CryCard> createState() => _CryCardState();
}

class _CryCardState extends State<CryCard> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color tint;
    final String headline;

    if (widget.crying) {
      tint = const Color(0xFFFFCDD2);
      headline = 'Crying now';
    } else if (widget.recentlyCrying) {
      tint = const Color(0xFFFFF4CC);
      headline = 'Recently crying';
    } else {
      tint = const Color(0xFFD5F5E3);
      headline = 'Calm';
    }

    return Card(
      child: Container(
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            _CryIcon(active: widget.crying),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _buildSubtitle(),
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildSubtitle() {
    if (widget.crying) {
      if (widget.sinceLastCry == null) {
        return 'Crying detected just now';
      }
      return 'Crying for ${_formatDuration(widget.sinceLastCry!)}';
    }
    if (widget.sinceLastCry == null) {
      return 'No cry detected yet';
    }
    final formatted = _formatDuration(widget.sinceLastCry!);
    if (widget.recentlyCrying) {
      return 'Last cry $formatted ago';
    }
    return 'No cry in last $formatted';
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours >= 1) {
      final hours = duration.inHours;
      final minutes = duration.inMinutes.remainder(60);
      if (minutes > 0) {
        return '$hours h $minutes m';
      }
      return '$hours h';
    }
    if (duration.inMinutes >= 1) {
      final minutes = duration.inMinutes;
      return '$minutes min';
    }
    final seconds = duration.inSeconds;
    return '$seconds s';
  }
}

class _MutedChip extends StatelessWidget {
  const _MutedChip({required this.remaining});

  final Duration? remaining;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = remaining == null
        ? 'Muted'
        : 'Muted ${_formatRemaining(remaining!)} left';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.notifications_off, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge,
          ),
        ],
      ),
    );
  }

  String _formatRemaining(Duration duration) {
    if (duration.inMinutes >= 1) {
      final minutes = duration.inMinutes;
      final seconds =
          duration.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$minutes:$seconds';
    }
    final seconds = duration.inSeconds;
    return '${seconds}s';
  }
}

class _CryIcon extends StatefulWidget {
  const _CryIcon({required this.active});

  final bool active;

  @override
  State<_CryIcon> createState() => _CryIconState();
}

class _CryIconState extends State<_CryIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.9,
      upperBound: 1.1,
    );
    if (widget.active) {
      _controller.repeat(reverse: true);
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant _CryIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.active
        ? const Color(0xFFD64545)
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6);

    return ScaleTransition(
      scale: widget.active ? _controller : const AlwaysStoppedAnimation(1),
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.graphic_eq,
          size: 28,
          color: color,
        ),
      ),
    );
  }
}

class _OfflineInfoCard extends StatelessWidget {
  const _OfflineInfoCard({
    required this.lastConnectedTime,
    this.lastDeviceName,
  });

  final DateTime lastConnectedTime;
  final String? lastDeviceName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeSinceConnection = DateTime.now().difference(lastConnectedTime);
    final deviceName = lastDeviceName ?? 'Baby Monitor';

    return Card(
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.wifi_off,
                size: 24,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Device offline',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Last seen: ${_formatTimeSince(timeSinceConnection)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    deviceName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimeSince(Duration duration) {
    if (duration.inDays > 0) {
      final days = duration.inDays;
      return days == 1 ? '1 day ago' : '$days days ago';
    }
    if (duration.inHours > 0) {
      final hours = duration.inHours;
      return hours == 1 ? '1 hour ago' : '$hours hours ago';
    }
    if (duration.inMinutes > 0) {
      final minutes = duration.inMinutes;
      return minutes == 1 ? '1 minute ago' : '$minutes minutes ago';
    }
    return 'Just now';
  }
}

class FanCard extends StatefulWidget {
  const FanCard({
    super.key,
    required this.fanRunning,
  });

  final bool fanRunning;

  @override
  State<FanCard> createState() => _FanCardState();
}

class _FanCardState extends State<FanCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.fanRunning) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant FanCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fanRunning && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.fanRunning && _controller.isAnimating) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color tint;
    final String headline;
    final String subtitle;

    if (widget.fanRunning) {
      tint = const Color(0xFFB3E5FC); // Light blue for cooling
      headline = 'Fan running';
      subtitle = 'Cooling the room';
    } else {
      tint = theme.colorScheme.surfaceContainerHighest;
      headline = 'Fan off';
      subtitle = 'Temperature in range';
    }

    final iconColor = widget.fanRunning
        ? const Color(0xFF2196F3) // Blue when running
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6);

    return Card(
      child: Container(
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            RotationTransition(
              turns: widget.fanRunning ? _controller : const AlwaysStoppedAnimation(0),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.air,
                  size: 28,
                  color: iconColor,
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
