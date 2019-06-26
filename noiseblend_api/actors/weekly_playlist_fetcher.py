from concurrent.futures import CancelledError

from arq import cron

from .actor import Actor
from ..overrides import AppSpotify


class WeeklyPlaylistFetcher(Actor):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

    @cron(
        weekday="fri", hour=12, minute=0, timeout_seconds=-1, dft_queue=Actor.LOW_QUEUE
    )
    async def fetch(self):
        try:
            spotify = AppSpotify(
                dbpool=self.dbpool,
                readonly_dbpools=self.readonly_dbpools,
                redis=self.local_redis or self.redis,
            )
            async with spotify.async_db_session() as conn:
                await spotify.authenticate_server_pg(conn=conn)
                await spotify.fetch_playlists_pg(conn=conn)
        except CancelledError:
            pass
