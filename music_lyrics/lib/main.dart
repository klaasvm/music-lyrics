import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(200, 200),
    center: true,
    backgroundColor: Colors.white,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setResizable(false);
    await windowManager.setMinimumSize(const Size(350, 200));
    await windowManager.setMaximumSize(const Size(350, 200));
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Music Lyrics',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  Timer? _timer;
  Timer? _progressTimer;
  Map<String, dynamic>? _currentTrack;
  String _status = "Bezig met laden...";
  int _countdown = 5;
  int _localProgressMs = 0;
  int _lastUpdateTime = 0;

  @override
  void initState() {
    super.initState();
    _startSpotifyPolling();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _progressTimer?.cancel();
    super.dispose();
  }

  void _startSpotifyPolling() {
    // Haal direct de eerste keer op
    _getCurrentlyPlaying();
    
    // Start de countdown timer die elke seconde aftelt
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _countdown--;
      });
      
      // Als countdown op 0 is, haal nieuwe data op en reset countdown
      if (_countdown <= 0) {
        _getCurrentlyPlaying();
        _countdown = 5;
      }
    });

    // Start de progress timer die elke seconde de lokale progress bijwerkt
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_currentTrack != null && _status == "Speelt af") {
        final durationMs = _currentTrack!['duration_ms'] ?? 0;
        setState(() {
          // Voeg 1 seconde toe, maar niet verder dan de totale duur
          if (_localProgressMs < durationMs) {
            _localProgressMs += 1000;
          }
        });
      }
    });
  }

  Future<String> _loadSpotifyToken() async {
    try {
      final file = File('lib/spotify_token.json');
      final contents = await file.readAsString();
      final tokenData = json.decode(contents);
      return tokenData['access_token'];
    } catch (e) {
      throw Exception('Kan Spotify token niet laden: $e');
    }
  }

  Future<void> _getCurrentlyPlaying() async {
    try {
      final accessToken = await _loadSpotifyToken();
      
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/me/player/currently-playing'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final data = json.decode(response.body);
        
        if (data['is_playing'] == true && data['item'] != null) {
          final track = data['item'];
          final artists = (track['artists'] as List)
              .map((artist) => artist['name'])
              .join(', ');
          
          final progressMs = data['progress_ms'] ?? 0;
          final durationMs = track['duration_ms'] ?? 0;
          
          // Update lokale progress met de nieuwste data van de API
          _localProgressMs = progressMs;
          _lastUpdateTime = DateTime.now().millisecondsSinceEpoch;

          setState(() {
            _currentTrack = {
              'track_name': track['name'],
              'artists': artists,
              'album': track['album']['name'],
              'duration_ms': durationMs,
            };
            _status = "Speelt af";
          });
        } else {
          setState(() {
            _currentTrack = null;
            _status = "Geen muziek aan het spelen";
          });
        }
      } else if (response.statusCode == 204) {
        setState(() {
          _currentTrack = null;
          _status = "Geen muziek aan het spelen";
        });
      } else {
        setState(() {
          _status = "Fout bij ophalen data (${response.statusCode})";
        });
      }
    } catch (e) {
      setState(() {
        _status = "Verbindingsfout: ${e.toString()}";
      });
    }
  }

  String _formatProgress() {
    if (_currentTrack == null) return '';
    
    final durationMs = _currentTrack!['duration_ms'] ?? 0;
    final currentProgressMs = _localProgressMs;
    
    final progressMin = currentProgressMs ~/ 60000;
    final progressSec = (currentProgressMs % 60000) ~/ 1000;
    final durationMin = durationMs ~/ 60000;
    final durationSecond = (durationMs % 60000) ~/ 1000;
    
    return '${progressMin}:${progressSec.toString().padLeft(2, '0')} / ${durationMin}:${durationSecond.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: _currentTrack != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        '🎵 Je luistert momenteel naar:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Nummer: ${_currentTrack!['track_name']}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Artiest(en): ${_currentTrack!['artists']}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Album: ${_currentTrack!['album']}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Voortgang: ${_formatProgress()}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Update over: ${_countdown}s',
                        style: TextStyle(
                          fontSize: 12,
                          color: _countdown <= 2 ? Colors.orange : Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _status,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Update over: ${_countdown}s',
                          style: TextStyle(
                            fontSize: 12,
                            color: _countdown <= 2 ? Colors.orange : Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onPanStart: (details) {
                windowManager.startDragging();
              },
              child: const Icon(
                Icons.open_with,
                size: 24,
                color: Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
