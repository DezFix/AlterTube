import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Глобальные настройки (SharedPreferences + ChangeNotifier).
// Доступ: context.watch<AppSettings>() / context.read<AppSettings>()

class AppSettings extends ChangeNotifier {
  static const allCategories = [
    'sponsor',
    'selfpromo',
    'intro',
    'outro',
    'interaction',
    'preview',
    'music_offtopic',
  ];
  static const regions = ['auto', 'RU', 'UA', 'US', 'DE'];

  ThemeMode themeMode = ThemeMode.system;
  bool amoled = false; // true = чисто чёрный фон в тёмной теме
  bool welcomeDone = false; // true = Welcome уже показывали
  bool sbEnabled = true;
  Set<String> sbCategories = {'sponsor', 'selfpromo', 'intro', 'outro', 'interaction'};
  String backendUrl = ''; // напр. http://192.168.1.5:5000 — иначе напрямую к sponsor.ajay.app
  String region = 'auto';
  bool shortsAutoplay = true; // автопрокрутка Shorts к следующему по завершению
  bool personalizedFeed = true; // лента Видео подстраивается под подписки и просмотры

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values[p.getInt('themeMode') ?? ThemeMode.system.index];
    amoled = p.getBool('amoled') ?? false;
    welcomeDone = p.getBool('welcomeDone') ?? false;
    sbEnabled = p.getBool('sbEnabled') ?? true;
    sbCategories = (p.getStringList('sbCategories') ?? sbCategories.toList()).toSet();
    backendUrl = p.getString('backendUrl') ?? '';
    region = p.getString('region') ?? 'auto';
    shortsAutoplay = p.getBool('shortsAutoplay') ?? true;
    personalizedFeed = p.getBool('personalizedFeed') ?? true;
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('themeMode', themeMode.index);
    await p.setBool('amoled', amoled);
    await p.setBool('welcomeDone', welcomeDone);
    await p.setBool('sbEnabled', sbEnabled);
    await p.setStringList('sbCategories', sbCategories.toList());
    await p.setString('backendUrl', backendUrl);
    await p.setString('region', region);
    await p.setBool('shortsAutoplay', shortsAutoplay);
    await p.setBool('personalizedFeed', personalizedFeed);
  }

  Future<void> setTheme(ThemeMode m) async {
    themeMode = m;
    notifyListeners();
    await _save();
  }

  Future<void> setAmoled(bool v) async {
    amoled = v;
    notifyListeners();
    await _save();
  }

  Future<void> setWelcomeDone() async {
    welcomeDone = true;
    notifyListeners();
    await _save();
  }

  Future<void> setSb(bool v) async {
    sbEnabled = v;
    notifyListeners();
    await _save();
  }

  Future<void> toggleCategory(String c, bool v) async {
    if (v) {
      sbCategories.add(c);
    } else {
      sbCategories.remove(c);
    }
    notifyListeners();
    await _save();
  }

  Future<void> setBackend(String v) async {
    backendUrl = v.trim();
    notifyListeners();
    await _save();
  }

  Future<void> setRegion(String v) async {
    region = v;
    notifyListeners();
    await _save();
  }

  Future<void> setShortsAutoplay(bool v) async {
    shortsAutoplay = v;
    notifyListeners();
    await _save();
  }

  Future<void> setPersonalizedFeed(bool v) async {
    personalizedFeed = v;
    notifyListeners();
    await _save();
  }

  Future<void> resetAll() async {
    themeMode = ThemeMode.system;
    amoled = false;
    welcomeDone = false;
    sbEnabled = true;
    sbCategories = {'sponsor', 'selfpromo', 'intro', 'outro', 'interaction'};
    backendUrl = '';
    region = 'auto';
    shortsAutoplay = true;
    personalizedFeed = true;
    notifyListeners();
    await _save();
  }
}
