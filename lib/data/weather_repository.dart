import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Real ambient weather from Open-Meteo (free, no API key needed).
///
/// Used ONLY by the wall idle-screen header. Culiacán, Sinaloa is the
/// default because that is where the panel lives. Every failure (offline,
/// timeout, bad payload) returns null so the UI falls back to icon + date
/// instead of showing an invented temperature.
class WeatherReading {
  const WeatherReading({
    required this.tempC,
    required this.code,
    required this.isDay,
  });

  final double tempC;
  final int code;
  final bool isDay;

  String get label => '${tempC.toStringAsFixed(0)}°';
}

class WeatherRepository {
  WeatherRepository({
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client();

  static const double culicanLat = 24.81;
  static const double culicanLon = -107.39;

  /// In-memory cache so the idle screen can paint the temperature on its
  /// very first frame instead of flashing icon-only and popping it in
  /// seconds later. Warmed with [prefetch] while the home loads.
  static WeatherReading? _cache;
  static DateTime? _cacheTime;
  static const cacheMaxAge = Duration(minutes: 10);

  static WeatherReading? get cached {
    final reading = _cache;
    final at = _cacheTime;
    if (reading == null || at == null) return null;
    if (DateTime.now().difference(at) > cacheMaxAge) return null;
    return reading;
  }

  /// Fire-and-forget warm-up; safe to call from the home load path.
  static void prefetch() {
    WeatherRepository().current().then((reading) {
      if (reading != null) {
        _cache = reading;
        _cacheTime = DateTime.now();
      }
    });
  }

  final http.Client _client;
  final Duration timeout;

  void close() => _client.close();

  Future<WeatherReading?> current({
    double lat = culicanLat,
    double lon = culicanLon,
  }) async {
    try {
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': lat.toStringAsFixed(2),
        'longitude': lon.toStringAsFixed(2),
        'current': 'temperature_2m,weather_code,is_day',
        'timezone': 'auto',
        'forecast_days': '1',
      });
      final resp = await _client.get(uri).timeout(timeout);
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body);
      if (body is! Map<String, dynamic>) return null;
      final current = body['current'];
      if (current is! Map<String, dynamic>) return null;
      final temp = current['temperature_2m'];
      final code = current['weather_code'];
      if (temp is! num || code is! num) return null;
      final isDay = current['is_day'];
      final reading = WeatherReading(
        tempC: temp.toDouble(),
        code: code.toInt(),
        isDay: isDay is num ? isDay != 0 : true,
      );
      _cache = reading;
      _cacheTime = DateTime.now();
      return reading;
    } catch (_) {
      return null;
    }
  }
}

/// Maps an Open-Meteo weather code + day/night flag to a Material icon:
/// clear day → sun, clear night → moon, partly cloudy day → sun+cloud,
/// partly cloudy night → moon+cloud, and the rest shared day/night.
IconData weatherIconFor(int? code, {bool isDay = true}) {
  return switch (code) {
    0 when !isDay => Icons.nightlight_round,
    0 => Icons.wb_sunny,
    1 || 2 when !isDay => Icons.nights_stay,
    1 || 2 => Icons.wb_cloudy,
    3 || 45 || 48 => Icons.cloud,
    51 ||
    53 ||
    55 ||
    56 ||
    57 ||
    61 ||
    63 ||
    65 ||
    66 ||
    67 ||
    80 ||
    81 ||
    82 => Icons.umbrella,
    71 || 73 || 75 || 77 || 85 || 86 => Icons.ac_unit,
    95 || 96 || 99 => Icons.thunderstorm,
    _ => Icons.wb_cloudy,
  };
}
