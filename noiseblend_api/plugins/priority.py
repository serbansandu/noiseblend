from addict import Dict

PRIORITY = Dict(
    {
        "request": {
            "camelcase_to_snakecase": 0,
            "add_redis_pool": 1,
            "add_db_pool": 1,
            "add_spotify_client": 2,
            "authorize_request": 3,
            "add_arq_actors": 4,
            "add_influx_db_client": 4,
            "add_braintree_gateway": 4,
            "collect_metrics_before": 5,
            "check_etag": 6,
        },
        "response": {
            "snakecase_to_camelcase": 0,
            "close_spotify_client": 1,
            "cache_response": 2,
            "collect_metrics_after": 5,
        },
    }
)
