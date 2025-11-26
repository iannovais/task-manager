import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  static final ConnectivityService instance = ConnectivityService._init();
  ConnectivityService._init();

  final Connectivity _connectivity = Connectivity();
  final _connectivityController = StreamController<bool>.broadcast();

  bool _isOnline = false;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  Stream<bool> get onConnectivityChanged => _connectivityController.stream;

  bool get isOnline => _isOnline;

  Future<void> initialize() async {
    final result = await _connectivity.checkConnectivity();
    _isOnline = _hasConnection(result);

    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      final wasOnline = _isOnline;
      _isOnline = _hasConnection(result);

      if (wasOnline != _isOnline) {
        print('Conectividade mudou: ${_isOnline ? "ONLINE" : "OFFLINE"}');
        _connectivityController.add(_isOnline);
      }
    });

    print('ConnectivityService inicializado - Status: ${_isOnline ? "ONLINE" : "OFFLINE"}');
  }

  bool _hasConnection(List<ConnectivityResult> result) {
    return result.contains(ConnectivityResult.mobile) ||
           result.contains(ConnectivityResult.wifi) ||
           result.contains(ConnectivityResult.ethernet);
  }

  Future<bool> checkConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    _isOnline = _hasConnection(result);
    return _isOnline;
  }

  Future<void> waitForConnection({Duration timeout = const Duration(seconds: 30)}) async {
    if (_isOnline) return;

    final completer = Completer<void>();
    late StreamSubscription<bool> subscription;

    subscription = onConnectivityChanged.listen((isOnline) {
      if (isOnline && !completer.isCompleted) {
        completer.complete();
        subscription.cancel();
      }
    });

    Future.delayed(timeout, () {
      if (!completer.isCompleted) {
        subscription.cancel();
        completer.completeError(TimeoutException('Timeout aguardando conexão'));
      }
    });

    return completer.future;
  }

  void dispose() {
    _subscription?.cancel();
    _connectivityController.close();
  }
}
