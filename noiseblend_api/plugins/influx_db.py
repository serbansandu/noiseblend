import pandas as pd
from spf import SanicPlugin
from sanic.exceptions import InvalidUsage

from .. import config, logger
from ..helpers import fix_types, with_cache, with_cache_invalidation
from .priority import PRIORITY
from ..constants import VALID_MOMENTS, SIDEBAR_ATTRIBUTE_METRIC
from ..overrides import InfluxDBClientDataframe


class InfluxDB(SanicPlugin):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

    def on_registered(self, context, reg, *args, **kwargs):
        context.client = None


influx_db = InfluxDB()


@influx_db.middleware(priority=PRIORITY.request.add_influx_db_client, with_context=True)
async def add_influx_db_client(request, context):
    if request.method == "OPTIONS":
        return

    if not context.client:
        logger.debug("InfluxDB Client is None")
        context.client = InfluxDBClientDataframe(**config.influx.client)
        await context.client.create_database(db=config.influx.client.db)


@influx_db.route("/send-stats", methods=["POST"], with_context=True)
async def send_stats(request, context):
    spotify = context.shared.request[id(request)].spotify
    influx = context.client

    if not request.json:
        raise InvalidUsage("No values received")

    if isinstance(request.json, list):
        points = [
            {**item, "tags": {"user": spotify.user_id, **item.get("tags", {})}}
            for item in request.json
        ]
        for point in points:
            fix_types(point)

        await influx.write(points)

        if any(p["measurement"] == SIDEBAR_ATTRIBUTE_METRIC for p in points):
            return with_cache_invalidation(
                {}, method="GET", path="/attributes-usage", user_id=spotify.user_id
            )
        return {}

    point = {
        **request.json,
        "tags": {"user": spotify.user_id, **request.json.get("tags", {})},
    }
    fix_types(point)
    await influx.write(point)

    if point["measurement"] == SIDEBAR_ATTRIBUTE_METRIC:
        return with_cache_invalidation(
            {}, method="GET", path="/attributes-usage", user_id=spotify.user_id
        )
    return {}


@influx_db.route("/attributes-usage", with_context=True)
async def attributes_usage(request, context):
    spotify = context.shared.request[id(request)].spotify
    influx = context.client

    moment = request.args.get("moment")
    if not moment:
        raise InvalidUsage("Missing parameter `moment`")

    if moment not in VALID_MOMENTS:
        raise InvalidUsage(f"`moment` should be one of {', '.join(VALID_MOMENTS)}")

    results = await influx.query(
        f"""
        SELECT COUNT(*)
            FROM "noiseblend"."autogen"."{SIDEBAR_ATTRIBUTE_METRIC}"
            WHERE time > now() - 2w AND
            "user" = '{spotify.user_id}' AND
            "moment" = '{moment}'
    """
    )

    if (isinstance(results, pd.DataFrame) and results.empty) or (
        isinstance(results, dict) and not results
    ):
        resp = {}
    else:
        attributes = list(results.to_dict("index").values())[0]
        attributes = {a[6:]: v for a, v in attributes.items()}
        resp = attributes

    return with_cache(resp)
