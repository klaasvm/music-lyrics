import json
import spotipy
from spotipy.oauth2 import SpotifyOAuth

SPOTIPY_CLIENT_ID = "3b43c51d3d3c4ee9b1620afaa9be69de"
SPOTIPY_CLIENT_SECRET = "cf217ab014ef4712a126fc30a6a71cd7"
SPOTIPY_REDIRECT_URI = "https://www.klaasvm.com"
SCOPE = "user-read-currently-playing user-read-playback-state"

sp_oauth = SpotifyOAuth(
    client_id=SPOTIPY_CLIENT_ID,
    client_secret=SPOTIPY_CLIENT_SECRET,
    redirect_uri=SPOTIPY_REDIRECT_URI,
    scope=SCOPE
)

token_info = sp_oauth.get_access_token(as_dict=True)
if token_info:
    with open("spotify_token.json", "w") as f:
        json.dump(token_info, f, indent=4)
    print("Token opgeslagen in spotify_token.json")
else:
    print("OAuth flow niet gelukt. Probeer opnieuw.")