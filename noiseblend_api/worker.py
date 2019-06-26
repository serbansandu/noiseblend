import asyncio
import os
import time
from datetime import datetime
from functools import partial
from uuid import UUID

import addict
import asyncpg
import raven
import raven_aiohttp
from arq import BaseWorker
from arq.utils import RedisSettings
from spfy.asynch import Spotify

from . import __version__, config, logger
from .actors import Blender, Player, Radio, VolumeFader, WeeklyPlaylistFetcher
from .helpers import get_user_dict, init_db_connection

raven_transport = partial(raven_aiohttp.QueuedAioHttpTransport, workers=5, qsize=100)
sentry = raven.Client(
    dsn=config.sentry.dsn,
    transport=raven_transport,
    release=os.getenv("GIT_SHA", __version__),
    **config.sentry.params,
)

REDIS = config.worker.redis or config.redis


class Worker(BaseWorker):
    redis_settings = RedisSettings(
        pool_maxsize=REDIS.pool.maxsize, pool_minsize=REDIS.pool.minsize, **REDIS.auth
    )
    shadows = [VolumeFader, Player, WeeklyPlaylistFetcher, Blender, Radio]
    max_concurrent_tasks = 10000
    dbpool = None
    readonly_dbpools = []
    actor_dbpool = None
    actor_readonly_dbpools = []

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.last_health_info = None
        self.loop = self.loop or asyncio.get_event_loop()
        self.metrics = []

        self.loop.create_task(self.init_dbpools())

        # pylint: disable=unused-variable
        # @app.route("/metrics")
        # async def health_check(request):
        #     if request.token != config.stats.token:
        #         raise Unauthorized("Authentication required", scheme="Bearer")

        #     data = b""
        #     if self.metrics:
        #         data = parse_data(self.metrics)
        #         self.metrics = []

        #     return raw(data)

        # self.loop.create_task(app.create_server(host="0.0.0.0", port=9002))

    async def shadow_kwargs(self):
        kwargs = await super().shadow_kwargs()
        return {
            **kwargs,
            "dbpool": Worker.actor_dbpool,
            "readonly_dbpools": Worker.actor_readonly_dbpools,
        }

    async def init_dbpools(self):
        if not Worker.dbpool:
            Worker.dbpool = await asyncpg.create_pool(
                **config.db.connection, **config.db.pool.worker, init=init_db_connection
            )
            logger.info(
                "Created Worker DB Pool with min=%d max=%s",
                Worker.dbpool._minsize,
                Worker.dbpool._maxsize,
            )
        if not Worker.readonly_dbpools and config.db.replica:
            Worker.readonly_dbpools = await asyncio.gather(
                *[
                    asyncpg.create_pool(
                        **dbconfig, **config.db.pool.worker, init=init_db_connection
                    )
                    for dbconfig in config.db.replica
                ]
            )
            for pool in Worker.readonly_dbpools:
                logger.info(
                    "Created Worker Read-Only DB Pool with min=%d max=%s",
                    pool._minsize,
                    pool._maxsize,
                )

        if not Worker.actor_dbpool:
            Worker.actor_dbpool = await asyncpg.create_pool(
                **config.db.connection, **config.db.pool.actor, init=init_db_connection
            )
            logger.info(
                "Created Actor DB Pool with min=%d max=%s",
                Worker.actor_dbpool._minsize,
                Worker.actor_dbpool._maxsize,
            )
        if not Worker.actor_readonly_dbpools and config.db.replica:
            Worker.actor_readonly_dbpools = await asyncio.gather(
                *[
                    asyncpg.create_pool(
                        **dbconfig, **config.db.pool.actor, init=init_db_connection
                    )
                    for dbconfig in config.db.replica
                ]
            )
            for pool in Worker.actor_readonly_dbpools:
                logger.info(
                    "Created Actor Read-Only DB Pool with min=%d max=%s",
                    pool._minsize,
                    pool._maxsize,
                )

    @staticmethod
    def get_job_point(started_at, job, status):
        return {
            "time": datetime.utcnow(),
            "measurement": "jobs",
            "fields": {
                "in_queue_for": started_at - job.queued_at,
                "duration": time.time() - started_at,
            },
            "tags": {
                "status": status,
                "queue": job.queue,
                "name": f"{job.class_name}.{job.func_name}",
            },
        }

    def log_job_result(self, started_at, result, j):
        super().log_job_result(started_at, result, j)
        self.metrics.append(self.get_job_point(started_at, j, "DONE"))

    async def handle_stop_job(self, started_at, exc, j):
        await super().handle_stop_job(started_at, exc, j)
        self.metrics.append(self.get_job_point(started_at, j, "STOPPED"))

    async def record_health(self, redis_queues, queue_lookup):
        health_info_changed = await super().record_health(redis_queues, queue_lookup)

        if health_info_changed:
            health_info = self.get_health_check_info()
            try:
                self.metrics.append(
                    {
                        "time": datetime.utcnow(),
                        "measurement": "workers",
                        "fields": health_info,
                        "tags": {},
                    }
                )
            except:
                sentry.captureException()
        return health_info_changed

    def get_health_check_info(self):
        pending_tasks = sum(not t.done() for t in self.drain.pending_tasks.values())
        self.last_health_info = {
            "pending": pending_tasks,
            "complete": self.jobs_complete,
            "failed": self.jobs_failed,
            "timeout": self.jobs_timed_out,
            **self.queue_task_count,
        }

        return self.last_health_info

    async def handle_execute_exc(self, started_at, exc, j):
        self.metrics.append(self.get_job_point(started_at, j, "ERROR"))
        try:
            await super().handle_execute_exc(started_at, exc, j)
            try:
                spotify = addict.Dict(
                    user_id=UUID(j.args[0]),
                    dbpool=Worker.dbpool,
                    readonly_dbpools=Worker.readonly_dbpools,
                    ensure_db_pool=(lambda: asyncio.sleep(0)),
                )
                spotify.async_db_session = partial(Spotify.async_db_session, spotify)
                user_dict = await get_user_dict(spotify)
                sentry.user_context(user_dict)
            except:
                pass

            sentry.tags_context({"job": f"{j.class_name}.{j.func_name}"})
            sentry.extra_context(
                {
                    "id": j.id,
                    "queue": j.queue,
                    "queued_at": j.queued_at,
                    "unique": j.unique,
                    "timeout_seconds": j.timeout_seconds,
                    "args": j.args,
                    "kwargs": j.kwargs,
                    "started_at": started_at,
                }
            )
            try:
                raise exc

            except:
                sentry.captureException()
        except Exception as e:
            logger.exception(e)
