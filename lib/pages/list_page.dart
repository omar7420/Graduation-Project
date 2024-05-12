// ignore_for_file: no_leading_underscores_for_local_identifiers, unnecessary_null_comparison, avoid_print, use_super_parameters, library_private_types_in_public_api

import 'dart:async';
import 'dart:convert';
import 'dart:math' show asin, cos, pi, sqrt;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:location/location.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weather/extensions/capitalized.dart';
import 'package:weather/pages/home_page.dart';

import '../../models/models.dart';
import '../../models/weather_model.dart';

class CityList extends StatefulWidget {
  const CityList({super.key});

  @override
  State<CityList> createState() => _CityListState();
}

class _CityListState extends State<CityList> {
  List<Map<String, dynamic>> cities = [];
  List<Map<String, dynamic>> filteredCities = [];
  Map<String, List<Map<String, dynamic>>> _searchIndex = {};
  final TextEditingController _searchController = TextEditingController();
  bool searching = false;
  List<Weather> cityWeather = [];
  bool isLoading = true;
  bool edit = false;
  bool enabled = false;
  bool loading = true;
  WeatherResponse? _response;

  Future<WeatherResponse> getWeather(long, lat) async {
    final response = await http.get(Uri.parse(
        'https://api.openweathermap.org/data/2.5/weather?&lon=$long&lat=$lat&appid=18decebbe830c46f2003c45757d88283&units=metric'));
    final json = jsonDecode(response.body);
    var responsee = WeatherResponse.fromJson(json);
    setState(() => _response = responsee);

    return responsee;
  }

  Future<Object> fetchWeather() async {
    final prefs = await SharedPreferences.getInstance();
    cityWeather = [];
    List<dynamic> ctid = prefs.getStringList('cityIds') ?? [];
    String cittiesIds = ctid.join(',');
    final response = await http.get(Uri.parse(
        'http://api.openweathermap.org/data/2.5/group?id=$cittiesIds&APPID=18decebbe830c46f2003c45757d88283&units=metric'));

    if (response.statusCode == 200) {
      List<Weather> weatherData = [];
      Map<String, dynamic> values = json.decode(response.body);
      List<dynamic> list = values['list'];
      for (Map<String, dynamic> weather in list) {
        weatherData.add(Weather.fromJson(weather));
      }
      setState(() {
        cityWeather = weatherData;
      });
    }
    return cityWeather;
  }

  @override
  void initState() {
    super.initState();
    _determinePosition();
    fetchWeather();
    _loadCities();
  }

  void _loadCities() async {
    String data = await rootBundle.loadString('assets/json/citys.json');
    List<dynamic> _cities = json.decode(data);
    setState(() {
      cities = _cities.map((city) => Map<String, dynamic>.from(city)).toList();
      filteredCities = cities;
      isLoading = false;

      // Populate the search index
      _searchIndex = {};
      for (var city in cities) {
        String name =
            '${city['owm_city_name']}, ${city['admin_level_1_long']}, ${city['country_long']}';
        if (name.isNotEmpty) {
          // check if name is not empty
          String initial = name.substring(0, 1).toLowerCase();
          if (_searchIndex[initial] == null) {
            _searchIndex[initial] = [];
          }
          _searchIndex[initial]?.add(city);
        }
      }
    });
  }

  void _determinePosition() async {
    Location location = Location();

    bool _serviceEnabled;
    PermissionStatus _permissionGranted;

    _serviceEnabled = await location.serviceEnabled();
    if (!_serviceEnabled) {
      _serviceEnabled = await location.requestService();
      if (!_serviceEnabled) {
        return;
      }
    }

    _permissionGranted = await location.hasPermission();
    if (_permissionGranted == PermissionStatus.denied) {
      _permissionGranted = await location.requestPermission();
      if (_permissionGranted != PermissionStatus.granted) {
        return;
      }
    }

    setState(() {
      enabled = true;
    });
    LocationData _previousLocationData;

    LocationData _currentLocationData = await location.getLocation();

    location.onLocationChanged.listen((LocationData currentLocation) {
      double distanceInMeters = _calculateDistance(
          _currentLocationData.latitude,
          _currentLocationData.longitude,
          currentLocation.latitude,
          currentLocation.longitude);
      if (distanceInMeters > 500) {
        // change threshold as required
        _currentLocationData = currentLocation;
        getWeather(
            _currentLocationData.longitude, _currentLocationData.latitude);
      }
    });

    _previousLocationData = _currentLocationData;
    getWeather(_previousLocationData.longitude, _previousLocationData.latitude);
  }

  double _calculateDistance(lat1, lon1, lat2, lon2) {
    const p = pi / 180;
    const c = cos;
    final a = 0.5 -
        c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)) * 1000;
  }

  void _filterCities(String query) {
    List<String> searchTerms = query.split(",");
    if (searchTerms.isNotEmpty && searchTerms[0].isNotEmpty) {
      String initial = searchTerms[0].toLowerCase().substring(0, 1);
      if (_searchIndex[initial] != null) {
        setState(() {
          filteredCities = _searchIndex[initial]!.where((city) {
            String cityName = city['owm_city_name'].toLowerCase();
            String stateName = city['admin_level_1_long'].toLowerCase();
            String countryName = city['country_long'].toLowerCase();
            for (var term in searchTerms) {
              if (term.trim().isNotEmpty &&
                  !cityName.contains(term.trim().toLowerCase()) &&
                  !stateName.contains(term.trim().toLowerCase()) &&
                  !countryName.contains(term.trim().toLowerCase())) {
                return false;
              }
            }
            return true;
          }).toList();
        });
      } else {
        setState(() {
          filteredCities = [];
        });
      }
    } else {
      setState(() {
        filteredCities = [];
      });
    }
  }

  Future<void> saveCityIds(String cityId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> cityIds = prefs.getStringList('cityIds') ?? <String>[];
    if (!cityIds.contains(cityId)) {
      cityIds.add(cityId);
      await prefs.setStringList('cityIds', cityIds);
      fetchWeather();
    }
  }

  Future<void> removeCityIds(String cityId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> cityIds = prefs.getStringList('cityIds') ?? <String>[];
    if (cityIds.contains(cityId)) {
      cityIds.remove(cityId);
      await prefs.setStringList('cityIds', cityIds);
      fetchWeather();
    }
  }

  Future<List<String>> getCityIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('cityIds') ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(150, 30, 30, 60),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color.fromARGB(150, 30, 30, 60),
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: const Text(
          'Taks',
          style: TextStyle(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
        ),
        actions: [
          edit
              ? TextButton(
                  onPressed: () {
                    setState(() {
                      edit = false;
                    });
                  },
                  child: const Text(
                    'Done',
                    style: TextStyle(color: Colors.white),
                  ))
              : IconButton(
                  onPressed: () {
                    showCupertinoModalPopup<void>(
                      context: context,
                      builder: (BuildContext context) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 15.0, vertical: 23.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color.fromARGB(150, 50, 50, 150),
                              border:
                                  Border.all(color: Colors.white38, width: 2),
                              borderRadius:
                                  const BorderRadius.all(Radius.circular(15)),
                            ),
                            height: MediaQuery.of(context).size.height - 590,
                            child: Column(children: [
                              const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Padding(
                                    padding: EdgeInsets.only(top: 9, bottom: 4),
                                    child: DefaultTextStyle(
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold),
                                      child: Text(
                                        'Settings',
                                      ),
                                    ),
                                  )
                                ],
                              ),
                              Padding(
                                padding: const EdgeInsets.all(5.0),
                                child: Container(
                                  decoration: const BoxDecoration(
                                    borderRadius:
                                        BorderRadius.all(Radius.circular(9)),
                                    color: Color.fromARGB(255, 60, 60, 240),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.max,
                                    children: [
                                      Expanded(
                                          child: Row(
                                        children: [
                                          const Expanded(
                                            child: Padding(
                                              padding: EdgeInsets.all(7.0),
                                              child: DefaultTextStyle(
                                                  style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.bold),
                                                  child: Text('Edit List')),
                                            ),
                                          ),
                                          IconButton(
                                              onPressed: () {
                                                setState(() {
                                                  edit = true;
                                                  Navigator.of(context).pop();
                                                });
                                              },
                                              icon: const Icon(
                                                CupertinoIcons.pencil,
                                                color: Colors.white,
                                              ))
                                        ],
                                      ))
                                    ],
                                  ),
                                ),
                              )
                            ]),
                          ),
                        );
                      },
                    );
                  },
                  icon: const Icon(
                    CupertinoIcons.ellipsis_circle,
                    color: Colors.white,
                    size: 25,
                  ))
        ],
      ),
      body: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding:
                const EdgeInsets.only(top: 8, bottom: 8, left: 13, right: 13),
            child: CupertinoSearchTextField(
              itemSize: 18,
              placeholder: 'Search for a city',
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: Colors.white,
                  inherit: false),
              controller: _searchController,
              onSuffixTap: () {
                setState(() {
                  _searchController.text = '';
                  filteredCities = [];
                });
                FocusManager.instance.primaryFocus?.unfocus();
              },
              onChanged: (value) {
                isLoading ? _loadCities() : _filterCities(value);
              },
            ),
          ),
          Flexible(
              child: _searchController.text.isNotEmpty
                  ? filteredCities.isNotEmpty
                      ? ListView.builder(
                          shrinkWrap: true,
                          physics: const ClampingScrollPhysics(),
                          itemCount: 30,
                          itemBuilder: (context, index) {
                            if (index >= filteredCities.length) {
                              return const SizedBox.shrink();
                            }
                            final cityName =
                                filteredCities[index]['owm_city_name'];
                            final country =
                                filteredCities[index]['country_long'];
                            final state =
                                filteredCities[index]['admin_level_1_long'];
                            final teste = '$cityName, $state, $country';

                            final query = _searchController.text.toLowerCase();
                            final matchIndex =
                                teste.toLowerCase().indexOf(query);

                            if (matchIndex == -1) {
                              return const SizedBox.shrink();
                            }

                            final before = teste.substring(0, matchIndex);
                            final match = teste.substring(
                                matchIndex, matchIndex + query.length);
                            final after =
                                teste.substring(matchIndex + query.length);

                            return GestureDetector(
                              onTap: () {
                                saveCityIds(
                                    filteredCities[index]['owm_city_id']);
                                setState(() {
                                  _searchController.text = '';
                                  filteredCities = [];
                                });
                                FocusManager.instance.primaryFocus?.unfocus();
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(13.0),
                                child: RichText(
                                  text: TextSpan(
                                    children: [
                                      TextSpan(
                                        text: before,
                                        style: const TextStyle(
                                            color: Colors.white12),
                                      ),
                                      TextSpan(
                                        text: match,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold),
                                      ),
                                      TextSpan(
                                        text: after,
                                        style: const TextStyle(
                                            color: Colors.white12),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          })
                      : Text(_searchController.text)
                  : enabled && loading == true
                      ? ListView.builder(
                          itemCount: enabled
                              ? cityWeather.length + 1
                              : cityWeather.length,
                          itemBuilder: (ctx, index) {
                            if (index == 0 && enabled) {
                              return _response != null
                                  ? Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      child: Card(
                                        color: Colors.transparent,
                                        clipBehavior:
                                            Clip.antiAliasWithSaveLayer,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Stack(
                                            clipBehavior: Clip.none,
                                            alignment: Alignment.topLeft,
                                            children: [
                                              Ink.image(
                                                image: AssetImage(
                                                    'assets/images/${_response!.weatherInfo.icon}.jpeg'),
                                                height: 115,
                                                fit: BoxFit.cover,
                                                child: InkWell(
                                                  hoverColor: Colors.black,
                                                  onTap: () {
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                          maintainState: true,
                                                          builder: (context) =>
                                                              HomePage(
                                                                cityWeather:
                                                                    cityWeather,
                                                                indexx: index,
                                                                loc: true,
                                                                response:
                                                                    _response,
                                                              )),
                                                    );
                                                  },
                                                ),
                                              ),
                                              Column(
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                          child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(14.0),
                                                        child: Column(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .start,
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Row(
                                                              children: [
                                                                const Text(
                                                                  'My Location',
                                                                  style: TextStyle(
                                                                      color: Colors
                                                                          .white,
                                                                      fontSize:
                                                                          19,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w700),
                                                                ),
                                                                Lottie.asset(
                                                                    'assets/animations/green.json',
                                                                    repeat:
                                                                        true,
                                                                    reverse:
                                                                        true,
                                                                    height: 25)
                                                              ],
                                                            ),
                                                            Text(
                                                              _response!
                                                                  .cityName
                                                                  .toString(),
                                                              style: const TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                  fontSize: 13,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600),
                                                            ),
                                                            Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .only(
                                                                      top: 20),
                                                              child: Text(
                                                                _response!
                                                                    .weatherInfo
                                                                    .description
                                                                    .toTitleCase(),
                                                                style: const TextStyle(
                                                                    color: Colors
                                                                        .white,
                                                                    fontSize:
                                                                        13,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600),
                                                              ),
                                                            )
                                                          ],
                                                        ),
                                                      )),
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 22),
                                                        child: ClipRRect(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(12),
                                                          child: Container(
                                                            width: 80,
                                                            height: 78,
                                                            color: Colors
                                                                .transparent,
                                                            child: Stack(
                                                              children: [
                                                                BackdropFilter(
                                                                  filter:
                                                                      ImageFilter
                                                                          .blur(
                                                                    sigmaX: 9.0,
                                                                    sigmaY: 9.0,
                                                                  ),
                                                                  child:
                                                                      Container(),
                                                                ),
                                                                Container(
                                                                  decoration:
                                                                      BoxDecoration(
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                            12),
                                                                    border: Border.all(
                                                                        color: Colors
                                                                            .white
                                                                            .withOpacity(0.13)),
                                                                    gradient: LinearGradient(
                                                                        begin: Alignment
                                                                            .topLeft,
                                                                        end: Alignment
                                                                            .bottomRight,
                                                                        colors: [
                                                                          //begin color
                                                                          Colors
                                                                              .white
                                                                              .withOpacity(0.15),
                                                                          //end color
                                                                          Colors
                                                                              .white
                                                                              .withOpacity(0.05),
                                                                        ]),
                                                                  ),
                                                                ),
                                                                Center(
                                                                    child:
                                                                        Column(
                                                                  mainAxisAlignment:
                                                                      MainAxisAlignment
                                                                          .spaceEvenly,
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .max,
                                                                  children: [
                                                                    Text(
                                                                      '${_response!.tempInfo.temperature.toStringAsFixed(0)}\u00B0',
                                                                      style: const TextStyle(
                                                                          color: Colors
                                                                              .white,
                                                                          fontSize:
                                                                              28,
                                                                          fontWeight:
                                                                              FontWeight.w500),
                                                                    ),
                                                                    Row(
                                                                      mainAxisAlignment:
                                                                          MainAxisAlignment
                                                                              .center,
                                                                      children: [
                                                                        Text(
                                                                          'H:${_response!.tempInfo.temperature.toStringAsFixed(0)}\u00B0',
                                                                          style: const TextStyle(
                                                                              color: Colors.white,
                                                                              fontSize: 13,
                                                                              fontWeight: FontWeight.w600),
                                                                        ),
                                                                        const SizedBox(
                                                                          width:
                                                                              2,
                                                                        ),
                                                                        Text(
                                                                          'L:${_response!.tempInfo.temperature.toStringAsFixed(0)}\u00B0',
                                                                          style: const TextStyle(
                                                                              color: Colors.white,
                                                                              fontSize: 13,
                                                                              fontWeight: FontWeight.w600),
                                                                        ),
                                                                      ],
                                                                    )
                                                                  ],
                                                                )),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      )
                                                    ],
                                                  )
                                                ],
                                              )
                                            ]),
                                      ),
                                    )
                                  : Container();
                            } else {
                              int cityIndex = enabled ? index - 1 : index;
                              return edit == false
                                  ? GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                              maintainState: true,
                                              builder: (context) => HomePage(
                                                    cityWeather: cityWeather,
                                                    indexx: index,
                                                    loc: enabled,
                                                    response: _response,
                                                  )),
                                        );
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        child: Card(
                                          color: Colors.transparent,
                                          clipBehavior:
                                              Clip.antiAliasWithSaveLayer,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Stack(
                                              clipBehavior: Clip.none,
                                              alignment: Alignment.topLeft,
                                              children: [
                                                Ink.image(
                                                  image: cityIndex >= 0 &&
                                                          cityIndex <
                                                              cityWeather
                                                                  .length &&
                                                          cityWeather[cityIndex]
                                                                  .cityIcon !=
                                                              null
                                                      ? AssetImage(
                                                          'assets/images/${cityWeather[cityIndex].cityIcon}.jpeg')
                                                      : const AssetImage(
                                                          'assets/images/default.jpeg'),
                                                  height: 115,
                                                  fit: BoxFit.cover,
                                                  child: InkWell(
                                                    hoverColor: Colors.black,
                                                    onTap: () {
                                                      Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                          maintainState: true,
                                                          builder: (context) =>
                                                              HomePage(
                                                            cityWeather:
                                                                cityWeather,
                                                            indexx: index,
                                                            loc: enabled,
                                                            response: _response,
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ),
                                                Column(
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                            child: Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(14.0),
                                                          child: Column(
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .start,
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                cityIndex <
                                                                        cityWeather
                                                                            .length
                                                                    ? cityWeather[
                                                                            cityIndex]
                                                                        .cityName
                                                                    : 'Invalid City',
                                                                style: const TextStyle(
                                                                    color: Colors
                                                                        .white,
                                                                    fontSize:
                                                                        19,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700),
                                                              ),
                                                              if (cityIndex <
                                                                  cityWeather
                                                                      .length)
                                                                UnixTimestampClock(
                                                                  timezone: cityWeather[
                                                                          cityIndex]
                                                                      .cityTimezone
                                                                      .toInt(),
                                                                ),
                                                              Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .only(
                                                                        top:
                                                                            20),
                                                                child: cityWeather !=
                                                                            null &&
                                                                        cityIndex <
                                                                            cityWeather.length
                                                                    ? Text(
                                                                        cityWeather[cityIndex]
                                                                            .cityTempDesc
                                                                            .toTitleCase(),
                                                                        style:
                                                                            const TextStyle(
                                                                          color:
                                                                              Colors.white,
                                                                          fontSize:
                                                                              13,
                                                                          fontWeight:
                                                                              FontWeight.w600,
                                                                        ),
                                                                      )
                                                                    : const SizedBox(),
                                                              ),
                                                            ],
                                                          ),
                                                        )),
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal:
                                                                      22),
                                                          child: ClipRRect(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        12),
                                                            child: Container(
                                                              width: 80,
                                                              height: 78,
                                                              color: Colors
                                                                  .transparent,
                                                              child: Stack(
                                                                children: [
                                                                  BackdropFilter(
                                                                    filter:
                                                                        ImageFilter
                                                                            .blur(
                                                                      sigmaX:
                                                                          9.0,
                                                                      sigmaY:
                                                                          9.0,
                                                                    ),
                                                                    child:
                                                                        Container(),
                                                                  ),
                                                                  Container(
                                                                    decoration:
                                                                        BoxDecoration(
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                              12),
                                                                      border: Border.all(
                                                                          color: Colors
                                                                              .white
                                                                              .withOpacity(0.13)),
                                                                      gradient: LinearGradient(
                                                                          begin: Alignment
                                                                              .topLeft,
                                                                          end: Alignment
                                                                              .bottomRight,
                                                                          colors: [
                                                                            //begin color
                                                                            Colors.white.withOpacity(0.15),
                                                                            //end color
                                                                            Colors.white.withOpacity(0.05),
                                                                          ]),
                                                                    ),
                                                                  ),
                                                                  Center(
                                                                      child:
                                                                          Column(
                                                                    mainAxisAlignment:
                                                                        MainAxisAlignment
                                                                            .spaceEvenly,
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .max,
                                                                    children: [
                                                                      Text(
                                                                        cityIndex >= 0 &&
                                                                                cityIndex < cityWeather.length
                                                                            ? '${cityWeather[cityIndex].cityTemp.toStringAsFixed(0)}\u00B0'
                                                                            : 'Error: Invalid cityIndex',
                                                                        style: const TextStyle(
                                                                            color: Colors
                                                                                .white,
                                                                            fontSize:
                                                                                28,
                                                                            fontWeight:
                                                                                FontWeight.w500),
                                                                      ),
                                                                      Row(
                                                                        mainAxisAlignment:
                                                                            MainAxisAlignment.center,
                                                                        children: [
                                                                          Text(
                                                                            cityIndex >= 0 && cityIndex < cityWeather.length
                                                                                ? 'H:${cityWeather[cityIndex].cityHtemp.toStringAsFixed(0)}\u00B0'
                                                                                : 'Error: Invalid cityIndex',
                                                                            style: const TextStyle(
                                                                                color: Colors.white,
                                                                                fontSize: 13,
                                                                                fontWeight: FontWeight.w600),
                                                                          ),
                                                                          const SizedBox(
                                                                            width:
                                                                                2,
                                                                          ),
                                                                          Text(
                                                                            cityIndex >= 0 && cityIndex < cityWeather.length
                                                                                ? 'L:${cityWeather[cityIndex].cityLtemp.toStringAsFixed(0)}\u00B0'
                                                                                : 'Error: Invalid cityIndex',
                                                                            style: const TextStyle(
                                                                                color: Colors.white,
                                                                                fontSize: 13,
                                                                                fontWeight: FontWeight.w600),
                                                                          ),
                                                                        ],
                                                                      )
                                                                    ],
                                                                  )),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                        )
                                                      ],
                                                    )
                                                  ],
                                                )
                                              ]),
                                        ),
                                      ))
                                  : Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      child: Center(
                                        child: Card(
                                          clipBehavior:
                                              Clip.antiAliasWithSaveLayer,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(15),
                                          ),
                                          child: Stack(
                                              clipBehavior: Clip.none,
                                              alignment: Alignment.topLeft,
                                              children: [
                                                Ink.image(
                                                  image: AssetImage(
                                                      'assets/images/${cityWeather[cityIndex].cityIcon}.jpeg'),
                                                  height: 75,
                                                  fit: BoxFit.cover,
                                                  child: InkWell(
                                                    hoverColor: Colors.black,
                                                    onTap: () {
                                                      Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                            maintainState: true,
                                                            builder:
                                                                (context) =>
                                                                    HomePage(
                                                                      cityWeather:
                                                                          cityWeather,
                                                                      indexx:
                                                                          index,
                                                                      loc: true,
                                                                      response:
                                                                          _response,
                                                                    )),
                                                      );
                                                    },
                                                  ),
                                                ),
                                                Column(
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                            child: Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(14.0),
                                                          child: Column(
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .start,
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                cityWeather[
                                                                        cityIndex]
                                                                    .cityName,
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style: const TextStyle(
                                                                    color: Colors
                                                                        .white,
                                                                    fontSize:
                                                                        19,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700),
                                                              ),
                                                              if (cityIndex <
                                                                  cityWeather
                                                                      .length)
                                                                UnixTimestampClock(
                                                                  timezone: cityWeather[
                                                                          cityIndex]
                                                                      .cityTimezone
                                                                      .toInt(),
                                                                ),
                                                            ],
                                                          ),
                                                        )),
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal:
                                                                      22),
                                                          child: ClipRRect(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        12),
                                                            child: Container(
                                                              width: 45,
                                                              height: 45,
                                                              color: Colors
                                                                  .transparent,
                                                              child: Stack(
                                                                children: [
                                                                  BackdropFilter(
                                                                    filter:
                                                                        ImageFilter
                                                                            .blur(
                                                                      sigmaX:
                                                                          9.0,
                                                                      sigmaY:
                                                                          9.0,
                                                                    ),
                                                                    child:
                                                                        Container(),
                                                                  ),
                                                                  Container(
                                                                    decoration:
                                                                        BoxDecoration(
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                              12),
                                                                      border: Border.all(
                                                                          color: Colors
                                                                              .white
                                                                              .withOpacity(0.13)),
                                                                      gradient: LinearGradient(
                                                                          begin: Alignment
                                                                              .topLeft,
                                                                          end: Alignment
                                                                              .bottomRight,
                                                                          colors: [
                                                                            //begin color
                                                                            Colors.white.withOpacity(0.15),
                                                                            //end color
                                                                            Colors.white.withOpacity(0.05),
                                                                          ]),
                                                                    ),
                                                                  ),
                                                                  Center(
                                                                      child:
                                                                          Column(
                                                                    mainAxisAlignment:
                                                                        MainAxisAlignment
                                                                            .spaceEvenly,
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .max,
                                                                    children: [
                                                                      Text(
                                                                        '${cityWeather[cityIndex].cityTemp.toStringAsFixed(0)}\u00B0',
                                                                        style: const TextStyle(
                                                                            color: Colors
                                                                                .white,
                                                                            fontSize:
                                                                                17,
                                                                            fontWeight:
                                                                                FontWeight.w500),
                                                                      ),
                                                                    ],
                                                                  )),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        Container(
                                                          height: 75,
                                                          width: 59,
                                                          color: Colors.red,
                                                          child: IconButton(
                                                              onPressed: () {
                                                                // Check if cityWeather is not empty
                                                                if (cityWeather
                                                                    .isNotEmpty) {
                                                                  // Check if cityIndex is within the valid range
                                                                  if (cityIndex >=
                                                                          0 &&
                                                                      cityIndex <
                                                                          cityWeather
                                                                              .length) {
                                                                    // Call removeCityIds function with the cityId of the city at cityIndex
                                                                    removeCityIds(cityWeather[
                                                                            cityIndex]
                                                                        .cityId
                                                                        .toString());
                                                                  } else {
                                                                    print(
                                                                        'Error: Invalid city index');
                                                                  }
                                                                } else {
                                                                  print(
                                                                      'Error: cityWeather is empty');
                                                                }
                                                              },
                                                              icon: const Icon(
                                                                CupertinoIcons
                                                                    .delete,
                                                                color: Colors
                                                                    .white,
                                                              )),
                                                        ),
                                                      ],
                                                    )
                                                  ],
                                                ),
                                              ]),
                                        ),
                                      ));
                            }
                          },
                        )
                      : ListView.builder(
                          itemCount: enabled
                              ? cityWeather.length + 1
                              : cityWeather.length,
                          itemBuilder: (ctx, index) {
                            if (index == 0 && enabled) {
                              return _response != null
                                  ? Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      child: Card(
                                        clipBehavior:
                                            Clip.antiAliasWithSaveLayer,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Stack(
                                            clipBehavior: Clip.none,
                                            alignment: Alignment.topLeft,
                                            children: [
                                              Ink.image(
                                                image: AssetImage(
                                                    'assets/images/${_response!.weatherInfo.icon}.jpeg'),
                                                height: 115,
                                                fit: BoxFit.cover,
                                                child: InkWell(
                                                  hoverColor: Colors.black,
                                                  onTap: () {
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                          maintainState: true,
                                                          builder: (context) =>
                                                              HomePage(
                                                                cityWeather:
                                                                    cityWeather,
                                                                indexx: index,
                                                                loc: true,
                                                                response:
                                                                    _response,
                                                              )),
                                                    );
                                                  },
                                                ),
                                              ),
                                              Column(
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                          child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(14.0),
                                                        child: Column(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .start,
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Row(
                                                              children: [
                                                                const Text(
                                                                  'My Location',
                                                                  style: TextStyle(
                                                                      color: Colors
                                                                          .white,
                                                                      fontSize:
                                                                          19,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w700),
                                                                ),
                                                                Lottie.asset(
                                                                    'assets/animations/green.json',
                                                                    repeat:
                                                                        true,
                                                                    reverse:
                                                                        true,
                                                                    height: 25)
                                                              ],
                                                            ),
                                                            Text(
                                                              _response!
                                                                  .cityName
                                                                  .toString(),
                                                              style: const TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                  fontSize: 13,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600),
                                                            ),
                                                            Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .only(
                                                                      top: 20),
                                                              child: Text(
                                                                _response!
                                                                    .weatherInfo
                                                                    .description
                                                                    .toTitleCase(),
                                                                style: const TextStyle(
                                                                    color: Colors
                                                                        .white,
                                                                    fontSize:
                                                                        13,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600),
                                                              ),
                                                            )
                                                          ],
                                                        ),
                                                      )),
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 22),
                                                        child: ClipRRect(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(12),
                                                          child: Container(
                                                            width: 80,
                                                            height: 78,
                                                            color: Colors
                                                                .transparent,
                                                            child: Stack(
                                                              children: [
                                                                BackdropFilter(
                                                                  filter:
                                                                      ImageFilter
                                                                          .blur(
                                                                    sigmaX: 9.0,
                                                                    sigmaY: 9.0,
                                                                  ),
                                                                  child:
                                                                      Container(),
                                                                ),
                                                                Container(
                                                                  decoration:
                                                                      BoxDecoration(
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                            12),
                                                                    border: Border.all(
                                                                        color: Colors
                                                                            .white
                                                                            .withOpacity(0.13)),
                                                                    gradient: LinearGradient(
                                                                        begin: Alignment
                                                                            .topLeft,
                                                                        end: Alignment
                                                                            .bottomRight,
                                                                        colors: [
                                                                          //begin color
                                                                          Colors
                                                                              .white
                                                                              .withOpacity(0.15),
                                                                          //end color
                                                                          Colors
                                                                              .white
                                                                              .withOpacity(0.05),
                                                                        ]),
                                                                  ),
                                                                ),
                                                                Center(
                                                                    child:
                                                                        Column(
                                                                  mainAxisAlignment:
                                                                      MainAxisAlignment
                                                                          .spaceEvenly,
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .max,
                                                                  children: [
                                                                    Text(
                                                                      '${_response!.tempInfo.temperature.toStringAsFixed(0)}\u00B0',
                                                                      style: const TextStyle(
                                                                          color: Colors
                                                                              .white,
                                                                          fontSize:
                                                                              28,
                                                                          fontWeight:
                                                                              FontWeight.w500),
                                                                    ),
                                                                    Row(
                                                                      mainAxisAlignment:
                                                                          MainAxisAlignment
                                                                              .center,
                                                                      children: [
                                                                        Text(
                                                                          'H:${_response!.tempInfo.temperature.toStringAsFixed(0)}\u00B0',
                                                                          style: const TextStyle(
                                                                              color: Colors.white,
                                                                              fontSize: 13,
                                                                              fontWeight: FontWeight.w600),
                                                                        ),
                                                                        const SizedBox(
                                                                          width:
                                                                              2,
                                                                        ),
                                                                        Text(
                                                                          'L:${_response!.tempInfo.temperature.toStringAsFixed(0)}\u00B0',
                                                                          style: const TextStyle(
                                                                              color: Colors.white,
                                                                              fontSize: 13,
                                                                              fontWeight: FontWeight.w600),
                                                                        ),
                                                                      ],
                                                                    )
                                                                  ],
                                                                )),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      )
                                                    ],
                                                  )
                                                ],
                                              )
                                            ]),
                                      ),
                                    )
                                  : Container();
                            } else {
                              int cityIndex = enabled ? index - 1 : index;
                              return edit == false
                                  ? GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                              maintainState: true,
                                              builder: (context) => HomePage(
                                                    cityWeather: cityWeather,
                                                    indexx: index,
                                                    loc: enabled,
                                                    response: _response,
                                                  )),
                                        );
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        child: Card(
                                          color: Colors.transparent,
                                          clipBehavior:
                                              Clip.antiAliasWithSaveLayer,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Stack(
                                              clipBehavior: Clip.none,
                                              alignment: Alignment.topLeft,
                                              children: [
                                                Ink.image(
                                                  image: AssetImage(
                                                      'assets/images/${cityWeather[cityIndex].cityIcon}.jpeg'),
                                                  height: 115,
                                                  fit: BoxFit.cover,
                                                  child: InkWell(
                                                    hoverColor: Colors.black,
                                                    onTap: () {
                                                      Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                            maintainState: true,
                                                            builder:
                                                                (context) =>
                                                                    HomePage(
                                                                      cityWeather:
                                                                          cityWeather,
                                                                      indexx:
                                                                          index,
                                                                      loc:
                                                                          enabled,
                                                                      response:
                                                                          _response,
                                                                    )),
                                                      );
                                                    },
                                                  ),
                                                ),
                                                Column(
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                            child: Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(14.0),
                                                          child: Column(
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .start,
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                cityWeather[
                                                                        cityIndex]
                                                                    .cityName,
                                                                style: const TextStyle(
                                                                    color: Colors
                                                                        .white,
                                                                    fontSize:
                                                                        19,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700),
                                                              ),
                                                              if (cityIndex <
                                                                  cityWeather
                                                                      .length)
                                                                UnixTimestampClock(
                                                                  timezone: cityWeather[
                                                                          cityIndex]
                                                                      .cityTimezone
                                                                      .toInt(),
                                                                ),
                                                              Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .only(
                                                                        top:
                                                                            20),
                                                                child: Text(
                                                                  cityWeather[
                                                                          cityIndex]
                                                                      .cityTempDesc
                                                                      .toTitleCase(),
                                                                  style: const TextStyle(
                                                                      color: Colors
                                                                          .white,
                                                                      fontSize:
                                                                          13,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600),
                                                                ),
                                                              )
                                                            ],
                                                          ),
                                                        )),
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal:
                                                                      22),
                                                          child: ClipRRect(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        12),
                                                            child: Container(
                                                              width: 80,
                                                              height: 78,
                                                              color: Colors
                                                                  .transparent,
                                                              child: Stack(
                                                                children: [
                                                                  BackdropFilter(
                                                                    filter:
                                                                        ImageFilter
                                                                            .blur(
                                                                      sigmaX:
                                                                          9.0,
                                                                      sigmaY:
                                                                          9.0,
                                                                    ),
                                                                    child:
                                                                        Container(),
                                                                  ),
                                                                  Container(
                                                                    decoration:
                                                                        BoxDecoration(
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                              12),
                                                                      border: Border.all(
                                                                          color: Colors
                                                                              .white
                                                                              .withOpacity(0.13)),
                                                                      gradient: LinearGradient(
                                                                          begin: Alignment
                                                                              .topLeft,
                                                                          end: Alignment
                                                                              .bottomRight,
                                                                          colors: [
                                                                            //begin color
                                                                            Colors.white.withOpacity(0.15),
                                                                            //end color
                                                                            Colors.white.withOpacity(0.05),
                                                                          ]),
                                                                    ),
                                                                  ),
                                                                  Center(
                                                                      child:
                                                                          Column(
                                                                    mainAxisAlignment:
                                                                        MainAxisAlignment
                                                                            .spaceEvenly,
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .max,
                                                                    children: [
                                                                      Text(
                                                                        '${cityWeather[cityIndex].cityTemp.toStringAsFixed(0)}\u00B0',
                                                                        style: const TextStyle(
                                                                            color: Colors
                                                                                .white,
                                                                            fontSize:
                                                                                28,
                                                                            fontWeight:
                                                                                FontWeight.w500),
                                                                      ),
                                                                      Row(
                                                                        mainAxisAlignment:
                                                                            MainAxisAlignment.center,
                                                                        children: [
                                                                          Text(
                                                                            'H:${cityWeather[cityIndex].cityHtemp.toStringAsFixed(0)}\u00B0',
                                                                            style: const TextStyle(
                                                                                color: Colors.white,
                                                                                fontSize: 13,
                                                                                fontWeight: FontWeight.w600),
                                                                          ),
                                                                          const SizedBox(
                                                                            width:
                                                                                2,
                                                                          ),
                                                                          Text(
                                                                            'L:${cityWeather[cityIndex].cityLtemp.toStringAsFixed(0)}\u00B0',
                                                                            style: const TextStyle(
                                                                                color: Colors.white,
                                                                                fontSize: 13,
                                                                                fontWeight: FontWeight.w600),
                                                                          ),
                                                                        ],
                                                                      )
                                                                    ],
                                                                  )),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                        )
                                                      ],
                                                    )
                                                  ],
                                                )
                                              ]),
                                        ),
                                      ))
                                  : Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      child: Center(
                                        child: Card(
                                          clipBehavior:
                                              Clip.antiAliasWithSaveLayer,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(15),
                                          ),
                                          child: Stack(
                                              clipBehavior: Clip.none,
                                              alignment: Alignment.topLeft,
                                              children: [
                                                Ink.image(
                                                  image: AssetImage(
                                                      'assets/images/${cityWeather[cityIndex].cityIcon}.jpeg'),
                                                  height: 75,
                                                  fit: BoxFit.cover,
                                                  child: InkWell(
                                                    hoverColor: Colors.black,
                                                    onTap: () {
                                                      Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                            maintainState: true,
                                                            builder:
                                                                (context) =>
                                                                    HomePage(
                                                                      cityWeather:
                                                                          cityWeather,
                                                                      indexx:
                                                                          index,
                                                                      loc: true,
                                                                      response:
                                                                          _response,
                                                                    )),
                                                      );
                                                    },
                                                  ),
                                                ),
                                                Column(
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                            child: Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(14.0),
                                                          child: Column(
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .start,
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                cityWeather[
                                                                        cityIndex]
                                                                    .cityName,
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style: const TextStyle(
                                                                    color: Colors
                                                                        .white,
                                                                    fontSize:
                                                                        19,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700),
                                                              ),
                                                              if (cityIndex <
                                                                  cityWeather
                                                                      .length)
                                                                UnixTimestampClock(
                                                                  timezone: cityWeather[
                                                                          cityIndex]
                                                                      .cityTimezone
                                                                      .toInt(),
                                                                ),
                                                            ],
                                                          ),
                                                        )),
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal:
                                                                      22),
                                                          child: ClipRRect(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        12),
                                                            child: Container(
                                                              width: 45,
                                                              height: 45,
                                                              color: Colors
                                                                  .transparent,
                                                              child: Stack(
                                                                children: [
                                                                  BackdropFilter(
                                                                    filter:
                                                                        ImageFilter
                                                                            .blur(
                                                                      sigmaX:
                                                                          9.0,
                                                                      sigmaY:
                                                                          9.0,
                                                                    ),
                                                                    child:
                                                                        Container(),
                                                                  ),
                                                                  Container(
                                                                    decoration:
                                                                        BoxDecoration(
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                              12),
                                                                      border: Border.all(
                                                                          color: Colors
                                                                              .white
                                                                              .withOpacity(0.13)),
                                                                      gradient: LinearGradient(
                                                                          begin: Alignment
                                                                              .topLeft,
                                                                          end: Alignment
                                                                              .bottomRight,
                                                                          colors: [
                                                                            //begin color
                                                                            Colors.white.withOpacity(0.15),
                                                                            //end color
                                                                            Colors.white.withOpacity(0.05),
                                                                          ]),
                                                                    ),
                                                                  ),
                                                                  Center(
                                                                      child:
                                                                          Column(
                                                                    mainAxisAlignment:
                                                                        MainAxisAlignment
                                                                            .spaceEvenly,
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .max,
                                                                    children: [
                                                                      Text(
                                                                        '${cityWeather[cityIndex].cityTemp.toStringAsFixed(0)}\u00B0',
                                                                        style: const TextStyle(
                                                                            color: Colors
                                                                                .white,
                                                                            fontSize:
                                                                                17,
                                                                            fontWeight:
                                                                                FontWeight.w500),
                                                                      ),
                                                                    ],
                                                                  )),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        Container(
                                                          height: 75,
                                                          width: 59,
                                                          color: Colors.red,
                                                          child: IconButton(
                                                              onPressed: () {
                                                                removeCityIds(
                                                                    cityWeather[
                                                                            cityIndex]
                                                                        .cityId
                                                                        .toString());
                                                              },
                                                              icon: const Icon(
                                                                CupertinoIcons
                                                                    .delete,
                                                                color: Colors
                                                                    .white,
                                                              )),
                                                        ),
                                                      ],
                                                    )
                                                  ],
                                                ),
                                              ]),
                                        ),
                                      ));
                            }
                          },
                        )),
        ]),
      ),
    );
  }
}

class UnixTimestampClock extends StatefulWidget {
  final int timezone;
  const UnixTimestampClock({Key? key, required this.timezone})
      : super(key: key);

  @override
  _UnixTimestampClockState createState() => _UnixTimestampClockState();
}

class _UnixTimestampClockState extends State<UnixTimestampClock> {
  late Timer _timer;
  late DateTime _dateTime;
  var _timezone = 0;

  @override
  void initState() {
    super.initState();
    _timezone = widget.timezone;
    _timer = Timer.periodic(const Duration(seconds: 1), _updateDateTime);
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant UnixTimestampClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.timezone != oldWidget.timezone) {
      setState(() {
        _timezone = widget.timezone;
      });
    }
  }

  void _updateDateTime(Timer timer) {
    setState(() {
      _dateTime = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    _dateTime = DateTime.now();
    var date = _dateTime.add(Duration(
        seconds: _timezone.toInt() - DateTime.now().timeZoneOffset.inSeconds));
    var formattedTime = DateFormat.Hm().format(date);
    return Text(
      formattedTime,
      style: const TextStyle(
          color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
    );
  }
}
