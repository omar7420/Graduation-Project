import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';

class DataService {
  Future<WeatherResponse> getWeather(long, lat) async {
    final response = await http.get(Uri.parse(
        'https://api.openweathermap.org/data/2.5/weather?&lon=$long&lat=$lat&appid=18decebbe830c46f2003c45757d88283&units=metric'));
    final json = jsonDecode(response.body);
    return WeatherResponse.fromJson(json);
  }
}
