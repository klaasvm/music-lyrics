"""
Spotify Currently Playing Tracker
Dit script haalt op welk nummer je momenteel aan het luisteren bent via de Spotify API
"""

import os
from dotenv import load_dotenv
import spotipy
from spotipy.oauth2 import SpotifyOAuth

# Spotify API credentials - deze moet je instellen in een .env bestand
SPOTIPY_CLIENT_ID = "3b43c51d3d3c4ee9b1620afaa9be69de"
SPOTIPY_CLIENT_SECRET = "cf217ab014ef4712a126fc30a6a71cd7"
SPOTIPY_REDIRECT_URI = "https://www.klaasvm.com"

# Scope voor het lezen van currently playing track
SCOPE = 'user-read-currently-playing user-read-playback-state'

def get_currently_playing():
    """
    Haalt het huidige nummer op dat wordt afgespeeld op Spotify
    """
    try:
        # Authenticatie setup
        sp = spotipy.Spotify(auth_manager=SpotifyOAuth(
            client_id=SPOTIPY_CLIENT_ID,
            client_secret=SPOTIPY_CLIENT_SECRET,
            redirect_uri=SPOTIPY_REDIRECT_URI,
            scope=SCOPE
        ))
        
        # Haal huidige nummer op
        current_track = sp.current_user_playing_track()
        
        if current_track is None or not current_track.get('is_playing'):
            print("Er wordt momenteel geen muziek afgespeeld.")
            return None
        
        # Extract relevante informatie
        track = current_track['item']
        track_name = track['name']
        artists = ', '.join([artist['name'] for artist in track['artists']])
        album = track['album']['name']
        progress_ms = current_track['progress_ms']
        duration_ms = track['duration_ms']
        
        # Converteer milliseconden naar minuten:seconden
        progress_min = progress_ms // 60000
        progress_sec = (progress_ms % 60000) // 1000
        duration_min = duration_ms // 60000
        duration_sec = (duration_ms % 60000) // 1000
        
        # Print informatie
        print("🎵 Je luistert momenteel naar:")
        print(f"   Nummer: {track_name}")
        print(f"   Artiest(en): {artists}")
        print(f"   Album: {album}")
        print(f"   Voortgang: {progress_min}:{progress_sec:02d} / {duration_min}:{duration_sec:02d}")
        
        # Return track data als dictionary
        return {
            'track_name': track_name,
            'artists': artists,
            'album': album,
            'progress_ms': progress_ms,
            'duration_ms': duration_ms,
            'track_id': track['id'],
            'spotify_url': track['external_urls']['spotify']
        }
        
    except Exception as e:
        print(f"Er is een fout opgetreden: {e}")
        return None

if __name__ == "__main__":
    print("Spotify Currently Playing Tracker")
    print("-" * 40)
    
    track_info = get_currently_playing()
    
    if track_info:
        print(f"\n🔗 Spotify URL: {track_info['spotify_url']}")
