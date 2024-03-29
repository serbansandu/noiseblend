from .. import config
from ..cache import async_lru
from ..overrides import AppSpotify
from .actor import Actor


async def close_session(spotify):
    if spotify.session:
        await spotify.session.close()


class SpotifyActor(Actor):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

    @async_lru(size=50000, evict_callback=close_session)
    async def spotify(self, user_id, username):
        spotify = AppSpotify(
            user_id=user_id,
            username=username,
            client_id=config.spotify.client_id,
            client_secret=config.spotify.client_secret,
            redirect_uri=config.spotify.redirect_uri,
            redis=Actor.local_redis or self.redis,
            dbpool=self.dbpool,
            readonly_dbpools=self.readonly_dbpools,
        )
        await spotify.authenticate_user_pg(scope=config.spotify.scope)
        return spotify
