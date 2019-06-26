import asyncio
import concurrent

import braintree
from spf import SanicPlugin
from sanic.exceptions import InvalidUsage

from .. import config, logger
from ..helpers import get_user_dict, with_cache_invalidation
from .priority import PRIORITY

executor = concurrent.futures.ThreadPoolExecutor(max_workers=30)


class BraintreeGateway(SanicPlugin):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

    def on_registered(self, context, reg, *args, **kwargs):
        context.gateway = None


braintree_gateway = BraintreeGateway()


@braintree_gateway.middleware(
    priority=PRIORITY.request.add_braintree_gateway, with_context=True
)
async def add_braintree_gateway(request, context):
    if request.method == "OPTIONS":
        return

    if not context.gateway:
        logger.debug("Braintree not initialized.")
        loop = asyncio.get_event_loop()
        context.gateway = await loop.run_in_executor(
            executor,
            braintree.BraintreeGateway,
            braintree.Configuration(**config.braintree.auth),
        )


@braintree_gateway.route("/client-token", methods=["GET"], with_context=True)
async def client_token(request, context):
    gateway = context.gateway
    spotify = context.shared.request[id(request)].spotify
    loop = asyncio.get_event_loop()

    invalidate = False
    async with spotify.async_db_session() as conn:
        has_customer_id = await conn.fetchval(
            "SELECT has_customer_id FROM app_users WHERE id = $1", spotify.user_id
        )
        if not has_customer_id:
            result = await loop.run_in_executor(
                executor,
                gateway.customer.create,
                {"id": str(spotify.user_id), "first_name": spotify.username},
            )

            if not result.is_success:
                raise InvalidUsage(result.message)

            await conn.execute(
                "UPDATE app_users SET has_customer_id = TRUE WHERE id = $1",
                spotify.user_id,
            )
            invalidate = True
        token = await loop.run_in_executor(
            executor,
            gateway.client_token.generate,
            {"customer_id": str(spotify.user_id)},
        )
        resp = {"token": token}

        if invalidate:
            return with_cache_invalidation(
                resp, method="GET", path="/me", user_id=spotify.user_id
            )
        return resp


@braintree_gateway.route("/checkout", methods=["POST"], with_context=True)
async def create_purchase(request, context):
    gateway = context.gateway
    spotify = context.shared.request[id(request)].spotify
    loop = asyncio.get_event_loop()

    nonce_from_the_client = request.json.get("nonce")
    if not nonce_from_the_client:
        raise InvalidUsage("No payment method received from client")

    async with spotify.async_db_session() as conn:
        premium_price = await conn.fetchval(
            "SELECT premium_price FROM app_users WHERE id = $1", spotify.user_id
        )

        if premium_price:
            price = str(premium_price)
        else:
            price = str(config.braintree.amount)

        result = await loop.run_in_executor(
            executor,
            gateway.transaction.sale,
            {
                "amount": price,
                "payment_method_nonce": nonce_from_the_client,
                "options": {
                    "submit_for_settlement": True,
                    "store_in_vault_on_success": True,
                },
            },
        )

        if not result.is_success:
            raise InvalidUsage(result.message)

        await conn.execute(
            "UPDATE app_users SET premium = TRUE WHERE id = $1", spotify.user_id
        )

        return with_cache_invalidation(
            await get_user_dict(spotify, conn=conn),
            method="GET",
            path="/me",
            user_id=spotify.user_id,
        )
