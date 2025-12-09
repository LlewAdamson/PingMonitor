import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/ping_data.dart';
import '../models/url_status.dart';

class PingService {
  // Base URL for the CSV server
  static const String baseUrl = 'http://localhost:8000';
  
  Future<List<PingData>> fetchPingData({String? url, int limit = 1000}) async {
    try {
      final uri = Uri.parse('$baseUrl/ping-data').replace(
        queryParameters: {
          if (url != null) 'url': url,
          'limit': limit.toString(),
        },
      );
      
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final pingList = data.map((item) => PingData.fromJson(item)).toList();
        print('Successfully loaded ${pingList.length} ping records from API');
        return pingList;
      } else {
        print('Failed to fetch ping data: ${response.statusCode}');
        return _getMockData();
      }
    } catch (e) {
      print('Error fetching ping data from API: $e');
      return _getMockData();
    }
  }

  List<PingData> _getMockData() {
    final now = DateTime.now();
    final urls = ['g.co', 'github.com', 'microsoft.com'];
    final ips = ['8.8.8.8', '140.82.113.4', '13.107.42.14'];
    final statuses = ['Success', 'High Latency', 'Ping Failure'];
    
    final List<PingData> mockData = [];
    
    for (int i = 0; i < 100; i++) {
      final urlIndex = i % urls.length;
      final url = urls[urlIndex];
      final ip = ips[urlIndex];
      
      String status;
      double? responseTime;
      
      // Generate more realistic mock data
      final random = (i * 7 + 3) % 100; // Pseudo-random
      
      if (random < 75) {
        status = 'Success';
        responseTime = 20.0 + (random % 50); // 20-70ms
      } else if (random < 90) {
        status = 'High Latency';
        responseTime = 100.0 + (random % 200); // 100-300ms
      } else {
        status = 'Ping Failure';
        responseTime = null;
      }
      
      mockData.add(PingData(
        timestamp: now.subtract(Duration(seconds: i * 10)),
        url: url,
        ip: ip,
        status: status,
        responseTime: responseTime,
        count: i + 1,
      ));
    }
    
    return mockData;
  }

  Future<List<UrlStatus>> fetchUrlStatuses() async {
    // 1. Get existing ping data
    final allPings = await fetchPingData();
    print('Total ping records fetched: ${allPings.length}');
    
    final Map<String, List<PingData>> pingsByUrl = {};
    
    // Group pings by URL
    for (final ping in allPings) {
      if (!pingsByUrl.containsKey(ping.url)) {
        pingsByUrl[ping.url] = [];
      }
      pingsByUrl[ping.url]!.add(ping);
    }
    
    print('URLs found from ping data: ${pingsByUrl.keys.toList()}');
    for (final entry in pingsByUrl.entries) {
      print('${entry.key}: ${entry.value.length} records');
    }

    // 2. Fetch configured TARGET_URLS from /env-config
    final configuredUrls = <String>{};
    try {
      final configResponse = await http
          .get(Uri.parse('$baseUrl/env-config'))
          .timeout(const Duration(seconds: 10));

      if (configResponse.statusCode == 200) {
        final Map<String, dynamic> config = json.decode(configResponse.body);
        final targets = (config['TARGET_URLS'] ?? '').toString();
        configuredUrls.addAll(
          targets
              .split(',')
              .map((u) => u.trim())
              .where((u) => u.isNotEmpty),
        );
        print('Configured URLs from env-config: $configuredUrls');
      } else {
        print(
            'Failed to fetch env-config: ${configResponse.statusCode} ${configResponse.reasonPhrase}');
      }
    } catch (e) {
      print('Error fetching env-config: $e');
    }

    // 3. Build UrlStatus list for URLs that have ping data
    //    but only for URLs that are currently configured.
    final Map<String, UrlStatus> urlStatusesMap = {};

    for (final entry in pingsByUrl.entries) {
      final url = entry.key;

      // Skip URLs that are not in the configured set
      if (configuredUrls.isNotEmpty && !configuredUrls.contains(url)) {
        continue;
      }

      final pings = entry.value;
      pings.sort((a, b) => b.timestamp.compareTo(a.timestamp)); // Most recent first
      
      final latestPing = pings.isNotEmpty ? pings.first : null;
      
      // Count consecutive failures and latency alerts
      int consecutiveFailures = 0;
      int consecutiveLatencyAlerts = 0;
      
      for (final ping in pings) {
        if (ping.isFailure) {
          consecutiveFailures++;
        } else {
          break;
        }
      }
      
      for (final ping in pings) {
        if (ping.isHighLatency) {
          consecutiveLatencyAlerts++;
        } else {
          break;
        }
      }
      
      urlStatusesMap[url] = UrlStatus(
        url: url,
        ip: latestPing?.ip,
        latestPing: latestPing,
        recentPings: pings.take(50).toList(), // Last 50 pings
        consecutiveFailures: consecutiveFailures,
        consecutiveLatencyAlerts: consecutiveLatencyAlerts,
      );
    }

    // 4. Add configured URLs that have *no* ping data yet
    for (final url in configuredUrls) {
      if (!urlStatusesMap.containsKey(url)) {
        print('Configured URL with no data yet: $url');
        urlStatusesMap[url] = UrlStatus(
          url: url,
          ip: null,
          latestPing: null,
          recentPings: const [],
          consecutiveFailures: 0,
          consecutiveLatencyAlerts: 0,
        );
      }
    }

    final urlStatuses = urlStatusesMap.values.toList();
    urlStatuses.sort((a, b) => a.url.compareTo(b.url));
    return urlStatuses;
  }
}
