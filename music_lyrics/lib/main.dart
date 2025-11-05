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
    await windowManager.setMinimumSize(const Size(400, 300));
    await windowManager.setMaximumSize(const Size(400, 300));
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
  String? _syncedLyrics;
  String _currentLyricLine = "";
  bool _isLoadingLyrics = false;
  
  // Spotify API credentials
  static const String _clientId = "3b43c51d3d3c4ee9b1620afaa9be69de";
  static const String _clientSecret = "cf217ab014ef4712a126fc30a6a71cd7";

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
        
        // Update huidige lyric regel
        _updateCurrentLyric();
      }
    });
  }

  Future<String> _loadSpotifyToken() async {
    try {
      final file = File('lib/spotify_token.json');
      final contents = await file.readAsString();
      final tokenData = json.decode(contents);
      
      // Check if token is expired
      final expiresAt = tokenData['expires_at'];
      final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      
      if (currentTime >= expiresAt) {
        // Token is expired, refresh it
        await _refreshSpotifyToken(tokenData['refresh_token']);
        // Read the updated token
        final newContents = await file.readAsString();
        final newTokenData = json.decode(newContents);
        return newTokenData['access_token'];
      }
      
      return tokenData['access_token'];
    } catch (e) {
      throw Exception('Kan Spotify token niet laden: $e');
    }
  }

  Future<void> _refreshSpotifyToken(String refreshToken) async {
    try {
      final response = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': 'Basic ${base64Encode(utf8.encode('$_clientId:$_clientSecret'))}',
        },
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final newTokenData = {
          'access_token': data['access_token'],
          'token_type': data['token_type'],
          'expires_in': data['expires_in'],
          'refresh_token': refreshToken, // Keep the same refresh token
          'scope': data['scope'] ?? 'user-read-currently-playing user-read-playback-state',
          'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + data['expires_in'],
        };

        // Write updated token to file
        final file = File('lib/spotify_token.json');
        await file.writeAsString(json.encode(newTokenData));
      } else {
        throw Exception('Token refresh failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Token refresh error: $e');
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

          // Check of dit een nieuw nummer is
          final isNewTrack = _currentTrack == null || 
                           _currentTrack!['track_name'] != track['name'] ||
                           _currentTrack!['artists'] != artists;

          setState(() {
            _currentTrack = {
              'track_name': track['name'],
              'artists': artists,
              'album': track['album']['name'],
              'duration_ms': durationMs,
            };
            _status = "Speelt af";
          });

          // Haal lyrics op voor nieuw nummer
          if (isNewTrack) {
            final durationSeconds = (durationMs / 1000).round();
            _fetchLyrics(track['name'], artists, track['album']['name'], durationSeconds);
          }
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
      } else if (response.statusCode == 401) {
        setState(() {
          _status = "Token verlopen, probeer opnieuw...";
        });
        // Token refresh wordt automatisch geprobeerd bij volgende call
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

  Future<void> _fetchLyrics(String trackName, String artistName, String albumName, int durationSeconds) async {
    setState(() {
      _isLoadingLyrics = true;
    });

    try {
      final uri = Uri.parse('https://lrclib.net/api/get').replace(queryParameters: {
        'track_name': trackName,
        'artist_name': artistName,
        'album_name': albumName,
        'duration': durationSeconds.toString(),
      });

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'MusicLyrics v1.0.0 (Flutter App)',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _syncedLyrics = data['syncedLyrics'];
          _isLoadingLyrics = false;
        });
      } else {
        setState(() {
          _syncedLyrics = null;
          _currentLyricLine = "Geen songteksten gevonden";
          _isLoadingLyrics = false;
        });
      }
    } catch (e) {
      setState(() {
        _syncedLyrics = null;
        _currentLyricLine = "Fout bij ophalen songteksten";
        _isLoadingLyrics = false;
      });
    }
  }

  void _updateCurrentLyric() {
    if (_syncedLyrics == null || _syncedLyrics!.isEmpty) {
      return;
    }

    final lines = _syncedLyrics!.split('\n');
    String newLyricLine = "";
    
    for (String line in lines) {
      if (line.trim().isEmpty) continue;
      
      // Parse LRC format: [mm:ss.xx] text
      final match = RegExp(r'^\[(\d{2}):(\d{2})\.(\d{2})\]\s*(.*)').firstMatch(line);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final centiseconds = int.parse(match.group(3)!);
        final text = match.group(4)!;
        
        final timeMs = (minutes * 60 * 1000) + (seconds * 1000) + (centiseconds * 10);
        
        if (_localProgressMs >= timeMs) {
          newLyricLine = text;
        } else {
          break;
        }
      }
    }

    if (newLyricLine != _currentLyricLine) {
      setState(() {
        _currentLyricLine = newLyricLine;
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
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main lyrics display
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Current track info (smaller)
                  if (_currentTrack != null) ...[
                    Text(
                      _currentTrack!['track_name'],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _currentTrack!['artists'],
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 20),
                  ],
                  
                  // Main lyrics display
                  Expanded(
                    child: Center(
                      child: _isLoadingLyrics
                          ? const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(color: Colors.green),
                                SizedBox(height: 10),
                                Text(
                                  'Songteksten laden...',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            )
                          : Text(
                              _currentLyricLine.isEmpty 
                                  ? (_currentTrack != null 
                                      ? 'Geen songteksten beschikbaar' 
                                      : _status)
                                  : _currentLyricLine,
                              style: TextStyle(
                                fontSize: _currentLyricLine.isEmpty ? 16 : 24,
                                fontWeight: FontWeight.bold,
                                color: _currentLyricLine.isEmpty ? Colors.grey : Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),
                    ),
                  ),
                  
                  // Progress and countdown info
                  if (_currentTrack != null) ...[
                    Text(
                      _formatProgress(),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 5),
                  ],
                  Text(
                    'Update over: ${_countdown}s',
                    style: TextStyle(
                      fontSize: 10,
                      color: _countdown <= 2 ? Colors.orange : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Drag handle
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onPanStart: (details) {
                windowManager.startDragging();
              },
              child: const Icon(
                Icons.open_with,
                size: 20,
                color: Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
