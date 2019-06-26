import asyncio
from functools import partial

import raven
import raven_aiohttp
from sanic.exceptions import SanicException
from sanic.handlers import ErrorHandler
from sanic.response import text

from .helpers import get_user_dict

REQUEST_ATTRS = (
    "args",
    "body",
    "content_type",
    "cookies",
    "files",
    "form",
    "headers",
    "host",
    "ip",
    "json",
    "path",
    "port",
    "query_string",
    "scheme",
    "socket",
    "token",
    "uri_template",
    "url",
)


def get_request_attr(request, attr):
    try:
        return getattr(request, attr)
    except Exception:
        return None


raven_transport = partial(raven_aiohttp.QueuedAioHttpTransport, workers=5, qsize=100)


class SentryLogging(ErrorHandler):
    def __init__(self, *args, config=None, release=None, logger=None, **kwargs):
        super().__init__(*args, **kwargs)
        self.sentry = raven.Client(
            dsn=config.sentry.dsn,
            transport=raven_transport,
            release=release,
            **config.sentry.params
        )
        self.logger = logger

    async def log_to_sentry(self, request, exception):
        spotify = request.get("spotify")
        try:
            if spotify:
                try:
                    user_dict = await get_user_dict(spotify)
                    self.sentry.user_context(user_dict)
                except:
                    pass

            self.sentry.http_context(
                {k: get_request_attr(request, k) for k in REQUEST_ATTRS}
            )
            try:
                raise exception

            except:
                self.sentry.captureException()
        except Exception as e:
            self.logger.exception(e)

    def default(self, request, exception):
        asyncio.get_event_loop().create_task(self.log_to_sentry(request, exception))
        if issubclass(type(exception), SanicException):
            return super().default(request, exception)

        self.logger.exception(exception)
        return text("Internal Server Error", status=500)
