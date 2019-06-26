        import asyncio

import asyncpg
from spf import SanicPlugin

from .. import config, logger
from ..helpers import init_db_connection
from .priority import PRIORITY


class AsyncDB(SanicPlugin):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

    def on_registered(self, context, reg, *args, **kwargs):
        context.shared.dbpool = None
        context.shared.readonly_dbpools = []
        context.shared.dbpool_lock = None


asyncdb = AsyncDB()


@asyncdb.middleware(priority=PRIORITY.request.add_db_pool, with_context=True)
async def add_db_pool(request, context):
    if not context.shared.dbpool_lock:
        context.shared.dbpool_lock = asyncio.Lock()

    if not context.shared.dbpool or (
        not context.shared.readonly_dbpools and config.db.replica
    ):
        async with context.shared.dbpool_lock:
            if not context.shared.dbpool:
                context.shared.dbpool = await asyncpg.create_pool(
                    **config.db.connection,
                    **config.db.pool.api,
                    init=init_db_connection
                )
                logger.info(
                    "Created API DB Pool with min=%d max=%s",
                    context.shared.dbpool._minsize,
                    context.shared.dbpool._maxsize,
                )
            if not context.shared.readonly_dbpools and config.db.replica:
                context.shared.readonly_dbpools = await asyncio.gather(
                    *[
                        asyncpg.create_pool(
                            **dbconfig, **config.db.pool.api, init=init_db_connection
                        )
                        for dbconfig in config.db.replica
                    ]
                )
                for pool in context.shared.readonly_dbpools:
                    logger.info(
                        "Created API Read-Only DB Pool with min=%d max=%s",
                        pool._minsize,
                        pool._maxsize,
                    )

    request["dbpool"] = context.shared.dbpool
    request["readonly_dbpools"] = context.shared.readonly_dbpools
