import 'package:flutter/material.dart';
import '../../features/auth/models/user_model.dart';
import '../../features/card/models/digital_card_model.dart';

/// Global app state — accessed via `appState.xxx` anywhere.
/// Listen with `ListenableBuilder(listenable: appState, ...)`.
class AppState extends ChangeNotifier {
  UserModel? _currentUser;
  DigitalCardModel? _currentCard;
  bool _loadingUser = false;
  bool _loadingCard = false;
  String? _error;

  UserModel? get currentUser => _currentUser;
  DigitalCardModel? get currentCard => _currentCard;
  bool get loadingUser => _loadingUser;
  bool get loadingCard => _loadingCard;
  String? get error => _error;
  bool get isAuthenticated => _currentUser != null;

  void setUser(UserModel? user) {
    _currentUser = user;
    _error = null;
    notifyListeners();
  }

  void setCard(DigitalCardModel? card) {
    _currentCard = card;
    notifyListeners();
  }

  void updateCard(DigitalCardModel card) {
    _currentCard = card;
    notifyListeners();
  }

  void setLoadingUser(bool v) {
    _loadingUser = v;
    notifyListeners();
  }

  void setLoadingCard(bool v) {
    _loadingCard = v;
    notifyListeners();
  }

  void setError(String? e) {
    _error = e;
    notifyListeners();
  }

  void clear() {
    _currentUser = null;
    _currentCard = null;
    _loadingUser = false;
    _loadingCard = false;
    _error = null;
    notifyListeners();
  }
}

/// Global singleton — import and use directly.
final appState = AppState();
