import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';
import '../models/ping_data.dart';
import '../services/ping_service.dart';

class UrlDetailScreen extends StatefulWidget {
  final String url;
  final String? ip;

  const UrlDetailScreen({
    super.key,
    required this.url,
    this.ip,
  });

  @override
  State<UrlDetailScreen> createState() => _UrlDetailScreenState();
}

class _UrlDetailScreenState extends State<UrlDetailScreen> {
  final PingService _pingService = PingService();
  List<PingData> _pingData = [];
  bool _isLoading = true;
  String? _error;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final allPings = await _pingService.fetchPingData();
      final urlPings = allPings
          .where((ping) => ping.url == widget.url)
          .toList();

      if (mounted) {
        setState(() {
          _pingData = urlPings;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.url),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red),
            SizedBox(height: 16),
            Text('Error loading data'),
            SizedBox(height: 8),
            Text(_error!),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              child: Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_pingData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No data found for ${widget.url}'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryCards(),
            const SizedBox(height: 24),
            _buildLatencyChart(),
            const SizedBox(height: 24),
            _buildStatusChart(),
            const SizedBox(height: 24),
            _buildRecentPings(),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    // Always sort by most recent first so "latest" and averages are consistent
    final sortedPings = [..._pingData]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final latestPing = sortedPings.isNotEmpty ? sortedPings.first : null;

    // Use same window as latency chart: most recent 50 pings with a response time
    final recentLatencyPings = sortedPings
        .where((p) => p.responseTime != null)
        .take(50)
        .toList();

    double? avgLatency;
    if (recentLatencyPings.isNotEmpty) {
      final sum = recentLatencyPings
          .map((p) => p.responseTime!)
          .fold<double>(0.0, (a, b) => a + b);
      avgLatency = sum / recentLatencyPings.length;
    } else {
      avgLatency = null;
    }

    // Debug: log average so we can confirm it is changing over time
    // (Only in debug mode this will be visible.)
    // ignore: avoid_print
    print(
        'Avg latency for ${widget.url} over last ${recentLatencyPings.length} pings: ${avgLatency?.toStringAsFixed(2) ?? 'n/a'} ms');

    final successfulPings = sortedPings.where((p) => p.isSuccess).toList();
    final uptime = sortedPings.isNotEmpty
        ? (successfulPings.length / sortedPings.length) * 100
        : 0.0;

    return Row(
      children: [
        Expanded(
          child: _buildSummaryCard(
            'Current Status',
            latestPing?.statusIcon ?? '❓',
            latestPing?.status ?? 'Unknown',
            latestPing?.statusColor ?? Colors.grey,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSummaryCard(
            'Avg Latency',
            '⏱️',
            avgLatency != null ? '${avgLatency.toStringAsFixed(1)}ms' : '--',
            Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSummaryCard(
            'Uptime',
            '📈',
            '${uptime.toStringAsFixed(1)}%',
            Colors.green,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String title, String icon, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(icon, style: TextStyle(fontSize: 24)),
            SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLatencyChart() {
    final latencyData = _pingData
        .where((ping) => ping.responseTime != null)
        .take(50)
        .toList()
        .reversed
        .toList();

    if (latencyData.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text('Latency Chart', style: Theme.of(context).textTheme.titleMedium),
              SizedBox(height: 20),
              Text('No latency data available'),
            ],
          ),
        ),
      );
    }

    // X axis is the index in latencyData; keep that consistent for labels
    final spots = latencyData.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.responseTime!);
    }).toList();

    String _formatTimestampLabel(int index) {
      if (index < 0 || index >= latencyData.length) return '';
      final ts = latencyData[index].timestamp;
      // Show only HH:MM for readability
      final hh = ts.hour.toString().padLeft(2, '0');
      final mm = ts.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Latency Chart', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          return Text('${value.toInt()}ms', style: const TextStyle(fontSize: 10));
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: (latencyData.length / 4).clamp(1, double.infinity),
                        getTitlesWidget: (value, meta) {
                          final index = value.round();
                          final label = _formatTimestampLabel(index);
                          if (label.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              label,
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: true),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: Colors.blue,
                      barWidth: 2,
                      dotData: FlDotData(show: false),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChart() {
    final statusCounts = <String, int>{};
    for (final ping in _pingData.take(100)) {
      statusCounts[ping.status] = (statusCounts[ping.status] ?? 0) + 1;
    }

    final sections = statusCounts.entries.map((entry) {
      final status = entry.key;
      final count = entry.value;
      final percentage = (count / _pingData.length) * 100;
      
      Color color;
      switch (status) {
        case 'Success':
          color = Colors.green;
          break;
        case 'High Latency':
          color = Colors.orange;
          break;
        case 'Ping Failure':
          color = Colors.red;
          break;
        default:
          color = Colors.grey;
      }

      return PieChartSectionData(
        color: color,
        value: count.toDouble(),
        title: '${percentage.toStringAsFixed(1)}%',
        radius: 50,
        titleStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status Distribution', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  Expanded(
                    child: PieChart(
                      PieChartData(
                        sections: sections,
                        centerSpaceRadius: 40,
                        sectionsSpace: 2,
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: statusCounts.entries.map((entry) {
                      Color color;
                      switch (entry.key) {
                        case 'Success':
                          color = Colors.green;
                          break;
                        case 'High Latency':
                          color = Colors.orange;
                          break;
                        case 'Ping Failure':
                          color = Colors.red;
                          break;
                        default:
                          color = Colors.grey;
                      }
                      
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(entry.key, style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentPings() {
    final recentPings = _pingData.take(20).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recent Pings', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            ...recentPings.map((ping) => _buildPingListItem(ping)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildPingListItem(PingData ping) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: ping.statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ping.status,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: ping.statusColor,
                  ),
                ),
                Text(
                  ping.timestamp.toString().substring(0, 19),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          if (ping.responseTime != null)
            Text(
              '${ping.responseTime!.toStringAsFixed(1)}ms',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }
}
