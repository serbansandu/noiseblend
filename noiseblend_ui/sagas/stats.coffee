import { eventChannel } from 'redux-saga'
import { all, call, put, race, select, take } from 'redux-saga/effects'

import _ from 'lodash'

import { getMoment } from '~/lib/time'

import SpotifyActions from '~/redux/spotify'
import StatsActions, { StatsTypes } from '~/redux/stats'

import config from '~/config'


export send = (api) ->
    points = yield select((state) -> state.stats.queued)
    if points.length is 0
        yield return

    res = yield call(api.stats, points)
    unless res.ok
        yield return

    yield put(StatsActions.dequeue())

export fetchAttributesUsage = (api) ->
    res = yield call(api.attributesUsage, getMoment())
    unless res.ok
        yield return

    yield put(StatsActions.setAttributesUsage(res.data))

watchMessages = (socket) ->
    eventChannel((emit) -> (() -> socket.close()))

export sendWs = (socket) ->
    loop
        yield take(StatsTypes.SEND_WS)

        points = yield select((state) -> state.stats.queued)
        if points.length is 0
            yield return

        if socket.readyState is WebSocket.OPEN
            yield call([socket, socket.send], JSON.stringify(points))
            yield put(StatsActions.dequeue())


export openWebsocket = ({ authToken }) ->
    token = authToken ? yield select((state) -> state.auth.authToken)
    socket = new WebSocket("#{ config.WS_URL }/stats-collector?token=#{ token }")
    socketChannel = yield call(watchMessages, socket)

    { cancel } = yield race(
        task: call(sendWs, socket)
        cancel: take(StatsTypes.CLOSE_WEBSOCKET)
    )

    if cancel
        socketChannel.close()
