import asyncio
from base64 import b64encode
from datetime import datetime, timedelta
from hashlib import sha1
from itertools import chain
from uuid import UUID

import addict
import ujson
from dateutil import relativedelta as rld
from first import first
from fuzzywuzzy import fuzz
from spfy.cache import Image, ImageMixin, Playlist
from spfy.constants import AudioFeature
from spfy.util import normalize_features

from .constants import ALL_FIELDS, BLEND_ALLOWED_FIELDS, PLAYLIST_DESCRIPTIONS
from .sql import SQL

NEXT_FRIDAY_DELTA = rld.relativedelta(
    weekday=rld.FR, hour=13, minute=0, second=0, microsecond=0
)


def fuzzysearch(needle, haystack):
    if not isinstance(haystack, set):
        haystack = set(haystack)
    if needle in haystack:
        return needle
    return max(haystack, key=lambda hay: fuzz.ratio(needle, hay))


def plural(item):
    if item[-1] == "y":
        return f"{item[:-1]}ies"
    return f"{item}s"


def seconds_until_next_playlist_fetch(now=None):
    now = now or datetime.utcnow()

    friday = now + NEXT_FRIDAY_DELTA
    if now >= friday and now.day == friday.day:
        return 60 * 30

    return (next_friday(now) - now).total_seconds()


def next_friday(now=None):
    now = now or datetime.utcnow()
    friday = now + NEXT_FRIDAY_DELTA
    if friday <= now:
        friday = now + timedelta(days=1) + NEXT_FRIDAY_DELTA

    return friday


def with_cache(response, **cache):
    if isinstance(response, dict) and "__response__" in response:
        response = response["__response__"]
    return {"__cache__": cache or True, "__response__": response}


def with_cache_invalidation(response, **invalidate):
    if isinstance(response, dict) and "__response__" in response:
        response = response["__response__"]
    if "endpoints" in invalidate:
        invalidate = invalidate["endpoints"]
    elif invalidate:
        invalidate = [invalidate]
    return {"__invalidate__": invalidate, "__response__": response}


def get_request_id(
    request=None, method=None, path=None, user_id=None, without_user_id=False
):
    if request:
        if not without_user_id:
            spotify = request.get("spotify")
            if spotify:
                user_id = spotify.user_id
        method = request.method
        path = request.path

    if not (method and path and (user_id or without_user_id)):
        raise ValueError("Invalid caching parameters")

    key = "-".join([method, path, str(user_id or "")])
    return sha1(key.encode()).hexdigest()


async def get_devices_and_playback(spotify):
    playback, devices = await asyncio.gather(
        spotify.current_playback(retries=0), spotify.devices(), return_exceptions=True
    )
    if isinstance(playback, Exception):
        playback = None
    if isinstance(devices, Exception):
        devices = []
    devices = devices or []

    for device in devices:
        if playback:
            device.is_playing = playback.is_playing and device.is_active
        else:
            device.is_playing = False

    return {"devices": list(devices), "playback": playback and playback.to_dict()}


def fix_types(point):
    for tag, value in point["tags"].items():
        if not isinstance(value, str):
            point["tags"][tag] = str(value)

    for field, value in point["fields"].items():
        if isinstance(value, int):
            point["fields"][field] = float(value)
        elif isinstance(value, UUID):
            point["fields"][field] = str(value)
    return point


def assign_best_image(item, width=None, height=None):
    if item.images:
        if width:
            item["image"] = first(
                item.images, key=lambda i: i.width >= width, default=item.images[0]
            )
        elif height:
            item["image"] = first(
                item.images, key=lambda i: i.height >= height, default=item.images[0]
            )
        else:
            item["image"] = item.images[0]
    return item


async def assign_audio_features(spotify, tracks=None, playlist=None):
    if not tracks and playlist:
        tracks = [t["track"] for t in playlist["tracks"]["items"]]

    tracks_dict = {t["id"]: t for t in tracks}

    audio_features = await spotify.audio_features(tracks=tracks_dict.keys())

    track_ids = [a.id for a in audio_features if a]
    audio_feature_keys = {f.value for f in AudioFeature}
    audio_features = [
        {
            **{k: v for k, v in a.items() if k in audio_feature_keys},
            "popularity": tracks_dict.get(a.id, {}).get("popularity", 0),
        }
        for a in audio_features
        if a
    ]

    normalized_audio_features = normalize_features(audio_features, track_ids)
    audio_features = {i: a for a, i in zip(audio_features, track_ids)}

    for t in tracks:
        track_id = t["id"]
        if track_id in audio_features:
            t["audio_features"] = audio_features[track_id]
            t["normalized_audio_features"] = normalized_audio_features.loc[
                track_id
            ].to_dict()

    if playlist:
        for t, t2 in zip(playlist["tracks"]["items"], tracks):
            t["track"] = t2
        return playlist

    return tracks


# pylint: disable=no-member


async def get_playlist_description(spotify, playlist_id, conn=None) -> str:
    description = ""
    async with spotify.async_db_session(conn=conn, readonly=True) as conn:
        playlist = await conn.fetchrow(
            """
                SELECT p.*, c.name AS country_name FROM playlists p
                LEFT OUTER JOIN countries c ON c.code = p.country
                WHERE id = $1
            """,
            playlist_id,
        )
    playlist = addict.Dict(dict(playlist))

    if playlist.city:
        description = PLAYLIST_DESCRIPTIONS["city"].format(city=playlist.city)
    elif playlist.country:
        descriptions = PLAYLIST_DESCRIPTIONS["country"]
        if playlist.christmas:
            description = descriptions["pine_needle"]
        else:
            popularity = Playlist.Popularity(playlist.popularity).name.lower()
            description = descriptions["needle"][popularity]
        description = description.format(country=playlist.country_name.split(",")[0])
    elif playlist.genre:
        descriptions = PLAYLIST_DESCRIPTIONS["genre"]
        # pylint: disable=no-member
        popularity = Playlist.Popularity(playlist.popularity).name.lower()
        if playlist.meta:
            description = descriptions["meta"][popularity]
        else:
            description = descriptions["normal"][popularity]
        description = description.format(
            genre=playlist.genre.title(), year=playlist.year
        )
    description = f"{description}. Cloned from {playlist.name}."
    return description


async def assign_images(spotify, items, key, _type, width, height, conn=None):
    items_without_image = [
        it
        for it in items
        if not (it.get("playlist") or it["playlists"][0])["image"]["url"]
    ]
    if not items_without_image:
        return

    fields = await asyncio.gather(
        *[
            ImageMixin.get_image_fields(it[key], **{_type: it[key]})
            for it in items_without_image
        ]
    )
    async with spotify.async_db_session(conn=conn) as conn:
        for image_fields, updated_fields in fields:
            images = await ImageMixin.upsert_unsplash_image(
                conn, image_fields, **updated_fields
            )
            if images:
                image = ImageMixin.get_optimal_image(images, width=width, height=height)
                for it in items:
                    if it[key] == image[_type]:
                        it["image"] = dict(image)
                        break


async def add_image(spotify, playlist_id, image, conn=None):
    if image.startswith("https://mosaic.scdn.co"):
        return

    async with spotify.async_db_session(conn=conn, readonly=True) as conn:
        image_content = await Image.download_pg(conn, image)
        if image_content and len(image_content) <= 256 * 1024:
            image_content = b64encode(image_content)
            await spotify.user_playlist_upload_cover_image(
                spotify.username, playlist_id, image_content
            )


def make_columns_serializable(record):
    for col, val in record.items():
        if isinstance(val, UUID):
            record[col] = str(val)
    return record


async def get_user_dict(spotify, conn=None):
    if not spotify.user_id:
        return {}

    async with spotify.async_db_session(conn=conn, readonly=True) as conn:
        user_data_stmt = await conn.prepare(SQL.user_data)
        user_data = await user_data_stmt.fetchrow(spotify.user_id)
        if not user_data:
            return {}

        user = addict.Dict(
            {
                k: v
                for k, v in user_data.items()
                if k in (BLEND_ALLOWED_FIELDS if spotify.blend else ALL_FIELDS)
            }
        )
        user["last_fetch"] = datetime.utcnow()
        return make_columns_serializable(user.to_dict())


async def init_db_connection(conn):
    await conn.set_type_codec(
        "json", encoder=ujson.dumps, decoder=ujson.loads, schema="pg_catalog"
    )
    await conn.set_type_codec(
        "jsonb", encoder=ujson.dumps, decoder=ujson.loads, schema="pg_catalog"
    )


async def user_has_premium(spotify, conn=None):
    async with spotify.async_db_session(conn=conn, readonly=True) as conn:
        premium_stmt = await conn.prepare(SQL.has_premium)
        has_premium = await premium_stmt.fetchval(spotify.user_id)
    return has_premium


async def user_disliked_artists(spotify, conn=None):
    async with spotify.async_db_session(conn=conn, readonly=True) as conn:
        disliked_artists_stmt = await conn.prepare(SQL.disliked_artists)
        disliked_artists = await disliked_artists_stmt.fetch(spotify.user_id)
    return disliked_artists


async def start_playback(spotify, args, player, volume_fader):
    device = args.get("device")
    artist = args.get("artist")
    album = args.get("album")
    playlist = args.get("playlist")
    tracks = args.get("tracks")
    volume = args.get("volume")
    filter_explicit = args.get("filter_explicit")
    volume = args.get("volume")
    fade_params = args.get("fade")
    device_id = args.get("device_id")

    if volume is not None:
        await spotify.volume(volume, device=device)

    if tracks and filter_explicit:
        tracks = await asyncio.gather(
            *[spotify.tracks(tracks[i : i + 50]) for i in range(0, len(tracks), 50)]
        )
        tracks = chain.from_iterable(tracks)
        tracks = [t.id for t in tracks if not t.explicit]

    if not device:
        await player.play(
            spotify.user_id,
            spotify.username,
            device=device,
            artist=artist,
            album=album,
            playlist=playlist,
            tracks=tracks,
            volume=volume,
            fade=fade_params,
            device_id=device_id,
        )
    else:
        await spotify.start_playback(
            device=device,
            artist=artist,
            album=album,
            playlist=playlist,
            tracks=tracks,
            retries=0,
        )
        if fade_params:
            await volume_fader.fade(
                spotify.user_id, spotify.username, device=device, **fade_params
            )


def get_tuneable_attributes(attrs):
    params = {}
    if attrs:
        for attribute, value in attrs.items():
            if isinstance(value, list):
                params[f"min_{attribute}"] = str(value[0])
                params[f"max_{attribute}"] = str(value[1])
            elif value is not None:
                params[f"target_{attribute}"] = str(value)
    return params
