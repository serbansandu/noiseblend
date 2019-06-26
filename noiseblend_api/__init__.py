# pylint: disable=wrong-import-order
import logging
from pathlib import Path

import sanic
from spf import SanicPluginsFramework
from sanic import Sanic
from sanic_compress import Compress

__version__ = "1.0.0"
APP_NAME = "Noiseblend-API"

import os  # isort:skip

import kick  # isort:skip

kick.start(APP_NAME.lower())  # isort:skip

from kick import config, logger  # isort:skip
from spfy import config as spfy_config  # isort:skip
import json  # isort:skip

ROOT_DIR = Path(__file__).parents[1]
logging.basicConfig()

log_config = sanic.log.LOGGING_CONFIG_DEFAULTS

if os.getenv("DEBUG") == "true":
    print("DEBUG MODE")
    logging.getLogger("sanic_cors").setLevel(logging.DEBUG)
    logging.getLogger("aioinflux").setLevel(logging.DEBUG)
    logger.debug("SPFY Config: %s", json.dumps(spfy_config, indent=2))
    logger.debug("Noiseblend Config: %s", json.dumps(config, indent=2))
if os.getenv("PRODUCTION") == "true":
    del log_config["loggers"]["sanic.error"]
    del log_config["loggers"]["sanic.access"]
    log_config["loggers"]["root"]["level"] = "WARNING"


from .sentry import SentryLogging  # isort:skip


app = Sanic(
    error_handler=SentryLogging(
        config=config, release=os.getenv("GIT_SHA", __version__), logger=logger
    ),
    log_config=log_config,
)
Compress(app)
spf = SanicPluginsFramework(app)
app.static("/favicon.ico", str(ROOT_DIR / "favicon.ico"), name="favicon")
