import addict
from aioinflux import InfluxDBClient, serialization
from spfy.asynch import Spotify

from .db import AppUser
from .sql import SQL


# pylint: disable=too-few-public-methods,too-many-ancestors
class AppSpotify(Spotify):
    def __init__(self, *args, blend=None, **kwargs):
        self.blend = blend
        super().__init__(*args, **kwargs)

    @property
    def app_user(self):
        if not self.user:
            return None
        return AppUser.get(id=self.user.id) or AppUser(id=self.user.id)

    async def fetch_app_user(self, conn=None):
        if not self.user_id:
            return None

        async with self.async_db_session(conn=conn, readonly=True) as dbconn:
            app_user_stmt = await dbconn.prepare(SQL.app_user)
            app_user = await app_user_stmt.fetchrow(self.user_id)
            if not app_user:
                return None
        return addict.Dict(dict(app_user))


class InfluxDBClientDataframe(InfluxDBClient):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

    # pylint: disable=arguments-differ
    async def query(self, *args, **kwargs):
        res = await super().query(*args, **kwargs)
        return serialization.dataframe.serialize(res)
