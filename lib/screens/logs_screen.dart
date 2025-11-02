import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;

import '../state/monitor_state.dart';

enum TimeRange { hour, threeHours, day }

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 0;
  static const int _itemsPerPage = 20;
  TimeRange _cryTimeRange = TimeRange.day;
  TimeRange _tempTimeRange = TimeRange.day;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Duration _getRangeDuration(TimeRange range) {
    switch (range) {
      case TimeRange.hour:
        return const Duration(hours: 1);
      case TimeRange.threeHours:
        return const Duration(hours: 3);
      case TimeRange.day:
        return const Duration(hours: 24);
    }
  }

  void _loadMore() {
    setState(() {
      _currentPage++;
    });
  }

  void _showAddLogSheet(BuildContext context) {
    final state = context.read<BabyMonitorState>();
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        String? amount;
        String? note;
        CareLogType selected = CareLogType.feeding;
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: StatefulBuilder(builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add log', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ChoiceChip(label: const Text('Feeding'), selected: selected == CareLogType.feeding, onSelected: (v) => setState(() => selected = CareLogType.feeding)),
                    const SizedBox(width: 8),
                    ChoiceChip(label: const Text('Diaper'), selected: selected == CareLogType.diaper, onSelected: (v) => setState(() => selected = CareLogType.diaper)),
                    const SizedBox(width: 8),
                    ChoiceChip(label: const Text('Sleep'), selected: selected == CareLogType.sleep, onSelected: (v) => setState(() => selected = CareLogType.sleep)),
                  ],
                ),
                const SizedBox(height: 12),
                if (selected == CareLogType.feeding)
                  TextField(
                    decoration: const InputDecoration(labelText: 'Amount (e.g. 90 ml)'),
                    onChanged: (v) => amount = v,
                    keyboardType: TextInputType.text,
                  ),
                if (selected == CareLogType.diaper)
                  TextField(
                    decoration: const InputDecoration(labelText: 'Note (wet/soiled)'),
                    onChanged: (v) => note = v,
                    keyboardType: TextInputType.text,
                  ),
                if (selected == CareLogType.sleep)
                  TextField(
                    decoration: const InputDecoration(labelText: 'Duration or note'),
                    onChanged: (v) => amount = v,
                    keyboardType: TextInputType.text,
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    FilledButton(
                      onPressed: () {
                        state.addCareLog(type: selected, amount: amount, note: note);
                        Navigator.of(context).pop();
                      },
                      child: const Text('Save'),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ],
            );
          }),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<BabyMonitorState>();
    final theme = Theme.of(context);

    // Calculate analytics based on selected time ranges
    final now = DateTime.now();
    final cryRangeStart = now.subtract(_getRangeDuration(_cryTimeRange));
    final tempRangeStart = now.subtract(_getRangeDuration(_tempTimeRange));
    
    // Cry analytics
    final cryEventsInRange = state.cryEvents.where((e) => e.start.isAfter(cryRangeStart)).toList();
    final cryDurations = cryEventsInRange.where((e) => e.duration != null).map((e) => e.duration!).toList();
    final avgCryDuration = cryDurations.isEmpty 
        ? Duration.zero 
        : Duration(microseconds: cryDurations.map((d) => d.inMicroseconds).reduce((a, b) => a + b) ~/ cryDurations.length);
    
    // Temperature analytics
    final tempsInRange = state.tempHistory.where((t) => t.timestamp.isAfter(tempRangeStart)).toList();
    final tempValues = tempsInRange.map((t) => t.temperature).toList();
    final avgTemp = tempValues.isEmpty ? null : tempValues.reduce((a, b) => a + b) / tempValues.length;
    final minTemp = tempValues.isEmpty ? null : tempValues.reduce((a, b) => a < b ? a : b);
    final maxTemp = tempValues.isEmpty ? null : tempValues.reduce((a, b) => a > b ? a : b);

    // Care logs (still 24h)
    final last24h = now.subtract(const Duration(hours: 24));
    final careLogs24h = state.careLogs.where((l) => l.timestamp.isAfter(last24h)).toList();
    final feedingCount = careLogs24h.where((l) => l.type == CareLogType.feeding).length;
    final diaperCount = careLogs24h.where((l) => l.type == CareLogType.diaper).length;

    // Paginated events
    final totalEvents = state.events.length + state.careLogs.length;
    final itemsToShow = math.min((_currentPage + 1) * _itemsPerPage, totalEvents);
    
    // Combine and sort events and care logs
    final allItems = <dynamic>[...state.events, ...state.careLogs]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final paginatedItems = allItems.take(itemsToShow).toList();
    final hasMore = itemsToShow < totalEvents;

    return SafeArea(
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Analytics & Logs',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _showAddLogSheet(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add log'),
                  ),
                ],
              ),
            ),
          ),

          // Analytics Section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Analytics',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  
                  // Cry Analytics
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.graphic_eq, color: theme.colorScheme.primary, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text('Cry Activity', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                              ),
                              _RangeSelector(
                                selected: _cryTimeRange,
                                onChanged: (range) => setState(() => _cryTimeRange = range),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _AnalyticTile(
                                  label: 'Events',
                                  value: '${cryEventsInRange.length}',
                                  theme: theme,
                                ),
                              ),
                              Expanded(
                                child: _AnalyticTile(
                                  label: 'Avg Duration',
                                  value: _formatDuration(avgCryDuration),
                                  theme: theme,
                                ),
                              ),
                            ],
                          ),
                          if (cryEventsInRange.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 140,
                              child: _CryBarChart(
                                events: cryEventsInRange, 
                                range: _cryTimeRange,
                                theme: theme,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Temperature Analytics
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.thermostat, color: theme.colorScheme.primary, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text('Temperature', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                              ),
                              _RangeSelector(
                                selected: _tempTimeRange,
                                onChanged: (range) => setState(() => _tempTimeRange = range),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _AnalyticTile(
                                  label: 'Average',
                                  value: avgTemp != null ? '${avgTemp.toStringAsFixed(1)}°C' : '--',
                                  theme: theme,
                                ),
                              ),
                              Expanded(
                                child: _AnalyticTile(
                                  label: 'Min',
                                  value: minTemp != null ? '${minTemp.toStringAsFixed(1)}°C' : '--',
                                  theme: theme,
                                ),
                              ),
                              Expanded(
                                child: _AnalyticTile(
                                  label: 'Max',
                                  value: maxTemp != null ? '${maxTemp.toStringAsFixed(1)}°C' : '--',
                                  theme: theme,
                                ),
                              ),
                            ],
                          ),
                          if (tempsInRange.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 120,
                              child: _TempChart(
                                samples: tempsInRange, 
                                color: theme.colorScheme.primary, 
                                minValue: state.comfortMin, 
                                maxValue: state.comfortMax,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Care Log Analytics
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.event_note, color: theme.colorScheme.primary, size: 20),
                              const SizedBox(width: 8),
                              Text('Care Logs', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _AnalyticTile(
                                  label: 'Feedings',
                                  value: '$feedingCount',
                                  theme: theme,
                                ),
                              ),
                              Expanded(
                                child: _AnalyticTile(
                                  label: 'Diapers',
                                  value: '$diaperCount',
                                  theme: theme,
                                ),
                              ),
                              Expanded(
                                child: _AnalyticTile(
                                  label: 'Total',
                                  value: '${careLogs24h.length}',
                                  theme: theme,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  
                  // Recent Activity Header
                  Text(
                    'Recent Activity',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          // Paginated Events List
          if (paginatedItems.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.event_note_outlined,
                      size: 64,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No activity yet',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index < paginatedItems.length) {
                      final item = paginatedItems[index];
                      if (item is MonitorEvent) {
                        return _EventItem(event: item, isLatest: index == 0);
                      } else if (item is CareLogEntry) {
                        return _CareLogItem(log: item);
                      }
                    }
                    return null;
                  },
                  childCount: paginatedItems.length,
                ),
              ),
            ),

          // Load More Button
          if (hasMore)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: OutlinedButton.icon(
                    onPressed: _loadMore,
                    icon: const Icon(Icons.expand_more),
                    label: Text('Load more (${totalEvents - itemsToShow} remaining)'),
                  ),
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 64)),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours >= 1) {
      final hours = duration.inHours;
      final minutes = duration.inMinutes.remainder(60);
      if (minutes > 0) return '${hours}h ${minutes}m';
      return '${hours}h';
    }
    if (duration.inMinutes >= 1) return '${duration.inMinutes}m';
    return '${duration.inSeconds}s';
  }
}

class _RangeSelector extends StatelessWidget {
  const _RangeSelector({required this.selected, required this.onChanged});

  final TimeRange selected;
  final Function(TimeRange) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RangeChip(
            label: '1H',
            selected: selected == TimeRange.hour,
            onTap: () => onChanged(TimeRange.hour),
          ),
          _RangeChip(
            label: '3H',
            selected: selected == TimeRange.threeHours,
            onTap: () => onChanged(TimeRange.threeHours),
          ),
          _RangeChip(
            label: '24H',
            selected: selected == TimeRange.day,
            onTap: () => onChanged(TimeRange.day),
          ),
        ],
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _CryBarChart extends StatefulWidget {
  const _CryBarChart({
    required this.events,
    required this.range,
    required this.theme,
  });

  final List<CryEvent> events;
  final TimeRange range;
  final ThemeData theme;

  @override
  State<_CryBarChart> createState() => _CryBarChartState();
}

class _CryBarChartState extends State<_CryBarChart> {
  int? _selectedBarIndex;

  void _handleTapDown(TapDownDetails details, int barIndex) {
    setState(() {
      _selectedBarIndex = barIndex;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Y-axis label
        SizedBox(
          width: 28,
          child: _CryYAxisLabels(events: widget.events, range: widget.range, theme: widget.theme),
        ),
        // Chart
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: _InteractiveCryChart(
                  events: widget.events,
                  range: widget.range,
                  theme: widget.theme,
                  selectedBarIndex: _selectedBarIndex,
                  onBarTapped: _handleTapDown,
                ),
              ),
              // X-axis labels
              const SizedBox(height: 4),
              _CryXAxisLabels(
                events: widget.events,
                range: widget.range, 
                theme: widget.theme,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CryYAxisLabels extends StatelessWidget {
  const _CryYAxisLabels({
    required this.events,
    required this.range,
    required this.theme,
  });

  final List<CryEvent> events;
  final TimeRange range;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox();

    final now = DateTime.now();
    int bucketCount;
    Duration bucketSize;

    switch (range) {
      case TimeRange.hour:
        bucketCount = 12;
        bucketSize = const Duration(minutes: 5);
        break;
      case TimeRange.threeHours:
        bucketCount = 12;
        bucketSize = const Duration(minutes: 15);
        break;
      case TimeRange.day:
        bucketCount = 24;
        bucketSize = const Duration(hours: 1);
        break;
    }

    final buckets = List<int>.filled(bucketCount, 0);
    for (final event in events) {
      final diff = now.difference(event.start);
      final bucketIndex = bucketCount - 1 - (diff.inMinutes / bucketSize.inMinutes).floor();
      if (bucketIndex >= 0 && bucketIndex < bucketCount) {
        buckets[bucketIndex]++;
      }
    }

    final maxCount = buckets.reduce((a, b) => a > b ? a : b);
    if (maxCount == 0) return const SizedBox();

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '$maxCount',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
        Text(
          '${(maxCount / 2).ceil()}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
        Text(
          '0',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _CryXAxisLabels extends StatelessWidget {
  const _CryXAxisLabels({
    required this.events,
    required this.range,
    required this.theme,
  });

  final List<CryEvent> events;
  final TimeRange range;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    int bucketCount;
    Duration bucketSize;

    switch (range) {
      case TimeRange.hour:
        bucketCount = 12;
        bucketSize = const Duration(minutes: 5);
        break;
      case TimeRange.threeHours:
        bucketCount = 12;
        bucketSize = const Duration(minutes: 15);
        break;
      case TimeRange.day:
        bucketCount = 24;
        bucketSize = const Duration(hours: 1);
        break;
    }

    // Generate labels for key buckets
    List<Widget> labels = [];
    final labelIndices = [0, bucketCount ~/ 2, bucketCount - 1];

    for (int idx in labelIndices) {
      final time = now.subtract(Duration(minutes: (bucketCount - 1 - idx) * bucketSize.inMinutes));
      String label;
      
      if (range == TimeRange.day) {
        label = '${time.hour}h';
      } else {
        label = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      }
      
      labels.add(
        Expanded(
          child: Text(
            label,
            textAlign: idx == 0 ? TextAlign.start : (idx == bucketCount - 1 ? TextAlign.end : TextAlign.center),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 9,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: labels,
      ),
    );
  }
}

class _InteractiveCryChart extends StatelessWidget {
  const _InteractiveCryChart({
    required this.events,
    required this.range,
    required this.theme,
    required this.selectedBarIndex,
    required this.onBarTapped,
  });

  final List<CryEvent> events;
  final TimeRange range;
  final ThemeData theme;
  final int? selectedBarIndex;
  final Function(TapDownDetails, int) onBarTapped;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int bucketCount;

        switch (range) {
          case TimeRange.hour:
            bucketCount = 12;
            break;
          case TimeRange.threeHours:
            bucketCount = 12;
            break;
          case TimeRange.day:
            bucketCount = 24;
            break;
        }

        final barWidth = constraints.maxWidth / bucketCount;

        return GestureDetector(
          onTapDown: (details) {
            final RenderBox box = context.findRenderObject() as RenderBox;
            final globalPosition = box.localToGlobal(details.localPosition);
            final barIndex = (details.localPosition.dx / barWidth).floor();
            if (barIndex >= 0 && barIndex < bucketCount) {
              onBarTapped(
                TapDownDetails(
                  globalPosition: globalPosition,
                  localPosition: details.localPosition,
                ),
                barIndex,
              );
            }
          },
          child: CustomPaint(
            painter: _CryBarChartPainter(
              events: events,
              range: range,
              color: theme.colorScheme.primary,
              selectedBarIndex: selectedBarIndex,
            ),
            size: Size.infinite,
          ),
        );
      },
    );
  }
}

class _CryBarChartPainter extends CustomPainter {
  _CryBarChartPainter({
    required this.events,
    required this.range,
    required this.color,
    this.selectedBarIndex,
  });

  final List<CryEvent> events;
  final TimeRange range;
  final Color color;
  final int? selectedBarIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (events.isEmpty) return;

    // Draw grid lines
    final gridPaint = Paint()
      ..color = const Color(0xFF000000).withValues(alpha: 0.05)
      ..strokeWidth = 1;

    // Horizontal grid lines
    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    final now = DateTime.now();
    int bucketCount;
    Duration bucketSize;

    switch (range) {
      case TimeRange.hour:
        bucketCount = 12; // 5-minute buckets
        bucketSize = const Duration(minutes: 5);
        break;
      case TimeRange.threeHours:
        bucketCount = 12; // 15-minute buckets
        bucketSize = const Duration(minutes: 15);
        break;
      case TimeRange.day:
        bucketCount = 24; // hourly buckets
        bucketSize = const Duration(hours: 1);
        break;
    }

    // Count cry events per bucket
    final buckets = List<int>.filled(bucketCount, 0);
    for (final event in events) {
      final diff = now.difference(event.start);
      final bucketIndex = bucketCount - 1 - (diff.inMinutes / bucketSize.inMinutes).floor();
      if (bucketIndex >= 0 && bucketIndex < bucketCount) {
        buckets[bucketIndex]++;
      }
    }

    final maxCount = buckets.reduce((a, b) => a > b ? a : b);
    if (maxCount == 0) return;

    final barWidth = size.width / bucketCount;

    // Draw trend line connecting the tops of bars (with breaks where count is 0)
    final List<Path> trendPaths = [];
    Path? currentTrendPath;
    
    for (int i = 0; i < bucketCount; i++) {
      final count = buckets[i];
      
      if (count > 0) {
        final barHeight = (count / maxCount) * size.height * 0.9;
        final x = i * barWidth + barWidth / 2; // Center of bar
        final y = size.height - barHeight;
        
        if (currentTrendPath == null) {
          // Start a new path segment
          currentTrendPath = Path();
          currentTrendPath.moveTo(x, y);
        } else {
          currentTrendPath.lineTo(x, y);
        }
      } else {
        // Break the trend line when count is 0
        if (currentTrendPath != null) {
          trendPaths.add(currentTrendPath);
          currentTrendPath = null;
        }
      }
    }
    
    // Add the last path segment if it exists
    if (currentTrendPath != null) {
      trendPaths.add(currentTrendPath);
    }
    
    // Draw all trend line segments
    final trendPaint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    
    for (final trendPath in trendPaths) {
      canvas.drawPath(trendPath, trendPaint);
    }

    // Draw bars
    for (int i = 0; i < bucketCount; i++) {
      final count = buckets[i];
      final isSelected = selectedBarIndex == i;
      
      if (count > 0) {
        final barHeight = (count / maxCount) * size.height * 0.9;
        final x = i * barWidth;
        final y = size.height - barHeight;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x + barWidth * 0.1, y, barWidth * 0.8, barHeight),
          const Radius.circular(4),
        );
        
        // Use different color for selected bar
        final paint = Paint()
          ..color = isSelected ? color.withValues(alpha: 1.0) : color.withValues(alpha: 0.8);
        canvas.drawRRect(rect, paint);
        
        // Add highlight border for selected bar
        if (isSelected) {
          final borderPaint = Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2;
          canvas.drawRRect(rect, borderPaint);
        }
        
        // Draw count label if space permits
        if (barHeight > 20) {
          final textPainter = TextPainter(
            text: TextSpan(
              text: '$count',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            textDirection: TextDirection.ltr,
          );
          textPainter.layout();
          textPainter.paint(
            canvas,
            Offset(x + barWidth / 2 - textPainter.width / 2, y + 4),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CryBarChartPainter oldDelegate) {
    return oldDelegate.events != events || 
           oldDelegate.range != range || 
           oldDelegate.selectedBarIndex != selectedBarIndex;
  }
}

class _AnalyticTile extends StatelessWidget {
  const _AnalyticTile({
    required this.label,
    required this.value,
    required this.theme,
  });

  final String label;
  final String value;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _EventItem extends StatelessWidget {
  const _EventItem({
    required this.event,
    required this.isLatest,
  });

  final MonitorEvent event;
  final bool isLatest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isLatest
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    final backgroundColor = isLatest
        ? theme.colorScheme.primary.withValues(alpha: 0.08)
        : Colors.transparent;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: isLatest
            ? Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.2),
                width: 1,
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              event.formattedTime,
              style: theme.textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                event.message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isLatest
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: isLatest ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CareLogItem extends StatelessWidget {
  const _CareLogItem({required this.log});

  final CareLogEntry log;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}';
    
    String label;
    IconData icon;
    Color iconColor;
    
    switch (log.type) {
      case CareLogType.feeding:
        label = 'Feeding ${log.amount ?? ''}';
        icon = Icons.restaurant;
        iconColor = Colors.orange;
        break;
      case CareLogType.diaper:
        label = 'Diaper ${log.note ?? ''}';
        icon = Icons.child_care;
        iconColor = Colors.blue;
        break;
      case CareLogType.sleep:
        label = 'Sleep ${log.amount ?? ''}';
        icon = Icons.bedtime;
        iconColor = Colors.purple;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            time,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: [const FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _TempChart extends StatefulWidget {
  const _TempChart({
    required this.samples,
    required this.color,
    this.minValue,
    this.maxValue,
  });

  final List<TempSample> samples;
  final Color color;
  final double? minValue;
  final double? maxValue;

  @override
  State<_TempChart> createState() => _TempChartState();
}

class _TempChartState extends State<_TempChart> {
  double? _touchX;
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showOverlay(BuildContext context, double touchX, Offset globalPosition, Size chartSize) {
    _removeOverlay();
    
    final overlayState = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          setState(() {
            _touchX = null;
          });
          _removeOverlay();
        },
        child: Stack(
          children: [
            _TempTooltip(
              samples: widget.samples,
              touchX: touchX,
              position: globalPosition,
              chartSize: chartSize,
              theme: Theme.of(context),
              minValue: widget.minValue,
              maxValue: widget.maxValue,
              onDismiss: () {
                setState(() {
                  _touchX = null;
                });
                _removeOverlay();
              },
            ),
          ],
        ),
      ),
    );
    
    overlayState.insert(_overlayEntry!);
  }

  void _handlePanUpdate(DragUpdateDetails details, Size size) {
    final touchX = details.localPosition.dx.clamp(0.0, size.width);
    final RenderBox box = context.findRenderObject() as RenderBox;
    final globalPosition = box.localToGlobal(Offset.zero);
    
    setState(() {
      _touchX = touchX;
    });
    
    _showOverlay(context, touchX, globalPosition, size);
  }

  void _handlePanEnd(DragEndDetails details) {
    setState(() {
      _touchX = null;
    });
    _removeOverlay();
  }

  void _handleTapDown(TapDownDetails details, Size size) {
    final touchX = details.localPosition.dx.clamp(0.0, size.width);
    final RenderBox box = context.findRenderObject() as RenderBox;
    final globalPosition = box.localToGlobal(Offset.zero);
    
    setState(() {
      _touchX = touchX;
    });
    
    _showOverlay(context, touchX, globalPosition, size);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        // Y-axis labels
        SizedBox(
          width: 35,
          child: widget.samples.isNotEmpty ? _TempYAxisLabels(
            samples: widget.samples,
            minValue: widget.minValue,
            maxValue: widget.maxValue,
            theme: theme,
          ) : const SizedBox(),
        ),
        // Chart
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      onPanUpdate: (details) => _handlePanUpdate(details, constraints.biggest),
                      onPanEnd: _handlePanEnd,
                      onTapDown: (details) => _handleTapDown(details, constraints.biggest),
                      onTapUp: (_) {
                        setState(() {
                          _touchX = null;
                        });
                        _removeOverlay();
                      },
                      child: CustomPaint(
                        painter: _TempChartPainter(
                          samples: widget.samples,
                          color: widget.color,
                          minValue: widget.minValue,
                          maxValue: widget.maxValue,
                          touchX: _touchX,
                        ),
                        size: Size.infinite,
                      ),
                    );
                  },
                ),
              ),
              // X-axis labels
              const SizedBox(height: 4),
              if (widget.samples.isNotEmpty)
                _TempXAxisLabels(samples: widget.samples, theme: theme),
            ],
          ),
        ),
      ],
    );
  }
}

class _TempYAxisLabels extends StatelessWidget {
  const _TempYAxisLabels({
    required this.samples,
    required this.theme,
    this.minValue,
    this.maxValue,
  });

  final List<TempSample> samples;
  final ThemeData theme;
  final double? minValue;
  final double? maxValue;

  @override
  Widget build(BuildContext context) {
    double minT = samples.map((s) => s.temperature).reduce((a, b) => a < b ? a : b);
    double maxT = samples.map((s) => s.temperature).reduce((a, b) => a > b ? a : b);
    if (minValue != null) minT = math.min(minT, minValue!);
    if (maxValue != null) maxT = math.max(maxT, maxValue!);
    if ((maxT - minT).abs() < 0.1) maxT = minT + 0.1;

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${maxT.toStringAsFixed(0)}°',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
        Text(
          '${((maxT + minT) / 2).toStringAsFixed(0)}°',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
        Text(
          '${minT.toStringAsFixed(0)}°',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _TempXAxisLabels extends StatelessWidget {
  const _TempXAxisLabels({
    required this.samples,
    required this.theme,
  });

  final List<TempSample> samples;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    if (samples.length < 2) return const SizedBox();

    final first = samples.first.timestamp;
    final last = samples.last.timestamp;
    final duration = last.difference(first);

    String formatTime(DateTime dt) {
      if (duration.inHours > 12) {
        return '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
      } else {
        return '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
      }
    }

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            formatTime(first),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
          Text(
            formatTime(last),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _TempTooltip extends StatelessWidget {
  const _TempTooltip({
    required this.samples,
    required this.touchX,
    required this.position,
    required this.chartSize,
    required this.theme,
    this.minValue,
    this.maxValue,
    required this.onDismiss,
  });

  final List<TempSample> samples;
  final double touchX; // Local x position within the chart
  final Offset position; // Global position of the chart's top-left corner
  final Size chartSize; // Size of the chart area
  final ThemeData theme;
  final double? minValue;
  final double? maxValue;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    // Calculate which sample point is closest to touchX
    final normalizedX = (touchX / chartSize.width).clamp(0.0, 1.0);
    final index = (normalizedX * (samples.length - 1)).round().clamp(0, samples.length - 1);
    final sample = samples[index];
    
    final time = sample.timestamp;
    final temp = sample.temperature;
    final timeStr = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    // Calculate temperature range with padding
    double minT = samples.map((s) => s.temperature).reduce((a, b) => a < b ? a : b);
    double maxT = samples.map((s) => s.temperature).reduce((a, b) => a > b ? a : b);
    if (minValue != null) minT = math.min(minT, minValue!);
    if (maxValue != null) maxT = math.max(maxT, maxValue!);
    if ((maxT - minT).abs() < 0.1) maxT = minT + 0.1;
    
    // Add padding (same as in painter)
    final range = maxT - minT;
    final padding = math.max(1.0, range * 0.1);
    maxT += padding;
    minT -= padding * 0.5;
    
    // Calculate Y position of the data point on the chart
    final normalizedY = ((temp - minT) / (maxT - minT)).clamp(0.0, 1.0);
    final dataPointY = chartSize.height - (normalizedY * chartSize.height);
    
    // Calculate X position of the data point
    final dataPointX = (index / (samples.length - 1)).clamp(0.0, 1.0) * chartSize.width;

    // Determine if temp is in comfort range
    String status = 'Normal';
    Color statusColor = const Color(0xFF2ECC71);
    
    if (minValue != null && maxValue != null) {
      if (temp > maxValue!) {
        status = 'High';
        statusColor = const Color(0xFFE74C3C);
      } else if (temp < minValue!) {
        status = 'Low';
        statusColor = const Color(0xFFE74C3C);
      }
    }

    const cardHeight = 90.0;
    const cardWidth = 130.0;
    
    // Position card at the tip of the vertical line (at the data point)
    final globalDataPointX = position.dx + dataPointX;
    final globalDataPointY = position.dy + dataPointY;
    
    final left = (globalDataPointX - cardWidth / 2).clamp(10.0, MediaQuery.of(context).size.width - cardWidth - 10);
    final top = (globalDataPointY - cardHeight - 10).clamp(10.0, MediaQuery.of(context).size.height - cardHeight - 10);

    return Positioned(
      left: left,
      top: top,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 130,
          height: 90,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.access_time, size: 12, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    timeStr,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.thermostat, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    '${temp.toStringAsFixed(1)}°C',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    status,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TempChartPainter extends CustomPainter {
  _TempChartPainter({
    required this.samples,
    required this.color,
    this.minValue,
    this.maxValue,
    this.touchX,
  });

  final List<TempSample> samples;
  final Color color;
  final double? minValue;
  final double? maxValue;
  final double? touchX;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    double minT = samples.map((s) => s.temperature).reduce((a, b) => a < b ? a : b);
    double maxT = samples.map((s) => s.temperature).reduce((a, b) => a > b ? a : b);
    if (minValue != null) minT = math.min(minT, minValue!);
    if (maxValue != null) maxT = math.max(maxT, maxValue!);
    if ((maxT - minT).abs() < 0.1) maxT = minT + 0.1;
    
    // Add padding at the top (at least 1 degree)
    final range = maxT - minT;
    final padding = math.max(1.0, range * 0.1);
    maxT += padding;
    minT -= padding * 0.5;

    // Draw grid lines
    final gridPaint = Paint()
      ..color = const Color(0xFF000000).withValues(alpha: 0.05)
      ..strokeWidth = 1;

    // Horizontal grid lines
    for (int i = 0; i <= 2; i++) {
      final y = size.height * i / 2;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    // Draw comfort zone reference lines if provided
    if (minValue != null && maxValue != null) {
      final maxY = size.height - ((maxValue! - minT) / (maxT - minT)).clamp(0.0, 1.0) * size.height;
      final minY = size.height - ((minValue! - minT) / (maxT - minT)).clamp(0.0, 1.0) * size.height;
      
      final referencePaint = Paint()
        ..color = const Color(0xFF2ECC71).withValues(alpha: 0.3)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      
      canvas.drawLine(Offset(0, maxY), Offset(size.width, maxY), referencePaint);
      canvas.drawLine(Offset(0, minY), Offset(size.width, minY), referencePaint);
    }

    final path = Path();
    final List<Path> fillPaths = []; // Multiple fill paths for segments
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

    // Draw comfort zones if min/max values are provided
    if (minValue != null && maxValue != null) {
      final maxY = size.height - ((maxValue! - minT) / (maxT - minT)).clamp(0.0, 1.0) * size.height;
      final minY = size.height - ((minValue! - minT) / (maxT - minT)).clamp(0.0, 1.0) * size.height;

      // Draw safe zone (green shading between minValue and maxValue)
      final safeZonePaint = Paint()
        ..color = const Color(0xFF2ECC71).withValues(alpha: 0.1)
        ..style = PaintingStyle.fill;
      
      canvas.drawRect(
        Rect.fromLTRB(0, maxY, size.width, minY),
        safeZonePaint,
      );

      // Create paths for extreme zones under the trend line
      final Path highZonePath = Path();
      final Path lowZonePath = Path();
      bool inHighZone = false;
      bool inLowZone = false;
      
      for (int i = 0; i < samples.length; i++) {
        final s = samples[i];
        
        // Skip zero values
        if (s.temperature.abs() < 0.01) {
          if (inHighZone) {
            highZonePath.close();
            inHighZone = false;
          }
          if (inLowZone) {
            lowZonePath.close();
            inLowZone = false;
          }
          continue;
        }
        
        final x = (i / (samples.length - 1)).clamp(0.0, 1.0) * size.width;
        final y = size.height - ((s.temperature - minT) / (maxT - minT)).clamp(0.0, 1.0) * size.height;
        
        // High zone: if temp is above maxValue, shade from maxY to trend line
        if (s.temperature > maxValue!) {
          if (!inHighZone) {
            highZonePath.moveTo(x, maxY);
            inHighZone = true;
          }
          highZonePath.lineTo(x, y);
        } else if (inHighZone) {
          highZonePath.lineTo(x, maxY);
          highZonePath.close();
          inHighZone = false;
        }
        
        // Low zone: if temp is below minValue, shade from trend line to minY
        if (s.temperature < minValue!) {
          if (!inLowZone) {
            lowZonePath.moveTo(x, minY);
            inLowZone = true;
          }
          lowZonePath.lineTo(x, y);
        } else if (inLowZone) {
          lowZonePath.lineTo(x, minY);
          lowZonePath.close();
          inLowZone = false;
        }
      }
      
      // Close paths if still in zone at the end
      if (inHighZone) {
        final lastX = size.width;
        highZonePath.lineTo(lastX, maxY);
        highZonePath.close();
      }
      if (inLowZone) {
        final lastX = size.width;
        lowZonePath.lineTo(lastX, minY);
        lowZonePath.close();
      }
      
      // Draw the extreme zone shading
      final extremePaint = Paint()
        ..color = const Color(0xFFE74C3C).withValues(alpha: 0.2)
        ..style = PaintingStyle.fill;
      
      canvas.drawPath(highZonePath, extremePaint);
      canvas.drawPath(lowZonePath, extremePaint);
    }

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    
    // Draw all fill path segments
    for (final fillPath in fillPaths) {
      canvas.drawPath(fillPath, fillPaint);
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, paint);

    // Draw touch indicator if touchX is set
    if (touchX != null && touchX! >= 0 && touchX! <= size.width) {
      // Find the corresponding point on the trend line
      final normalizedX = (touchX! / size.width).clamp(0.0, 1.0);
      final sampleIndex = (normalizedX * (samples.length - 1)).round().clamp(0, samples.length - 1);
      final sample = samples[sampleIndex];
      final x = (sampleIndex / (samples.length - 1)).clamp(0.0, 1.0) * size.width;
      final y = size.height - ((sample.temperature - minT) / (maxT - minT)).clamp(0.0, 1.0) * size.height;

      // Draw vertical line
      final linePaint = Paint()
        ..color = color.withValues(alpha: 0.5)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        linePaint,
      );

      // Draw circle at the intersection with trend line
      final circlePaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(Offset(x, y), 5, circlePaint);
      
      // Draw white border around circle
      final borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      
      canvas.drawCircle(Offset(x, y), 5, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TempChartPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.color != color ||
        oldDelegate.minValue != minValue ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.touchX != touchX;
  }
}
