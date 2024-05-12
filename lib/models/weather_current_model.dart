// ignore_for_file: non_constant_identifier_names

class WeatherCurrent {
  WeatherCurrent({
    required this.cityUiv,
  });
  num cityUiv;

  factory WeatherCurrent.fromJson(Map<String, dynamic> json) {
    return WeatherCurrent(
      cityUiv: json['current']['uvi'] ?? 0,
    );
  }
}

List<WeatherCurrent> WeatherCurrentList = [];
