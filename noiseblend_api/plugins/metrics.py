import time
from datetime import datetime

from aioinflux.serialization import serialize
from sanic.exceptions import Unauthorized
from sanic.response import raw
from spf import SanicPlugin

from .. import config, logger
from .priority import PRIORITY


class Metrics(SanicPlugin):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

    def on_registered(self, context, reg, *args, **kwargs):
        context.points = []


metrics = Metrics()


@metrics.middleware(priority=PRIORITY.request.collect_metrics_before, with_context=True)
async def collect_metrics_before(request, context):
    if request.path in config.stats.telegraf.endpoints:
        return
    context.request[id(request)].start_time = time.time()


@metrics.middleware(
    attach_to="response",
    relative="post",
    priority=PRIORITY.response.collect_metrics_after,
    with_context=True,
)
async def collect_metrics_after(request, response, context):
    if isinstance(response, dict):
        logger.error("Response is dict: %s", response)

    if request.path in config.stats.telegraf.endpoints:
        return response

    try:
        request_start_time = context.request[id(request)].start_time
    except (KeyError, AttributeError):
        return response

    context.points.append(
        {
            "measurement": "requests",
            "time": datetime.utcnow(),
            "tags": {
                "ip": request.ip,
                "host": request.host,
                "path": request.path,
                "status": response.status,
            },
            "fields": {
                "duration": time.time() - request_start_time,
                "size": len(response.body),
            },
        }
    )


@metrics.route("/metrics", with_context=True)
async def get_metrics(request, context):
    if request.token != config.stats.token:
        raise Unauthorized("Authentication required", scheme="Bearer")

    data = b""
    if context.points:
        data = serialize(context.points)
        context.points = []

    return raw(data)
