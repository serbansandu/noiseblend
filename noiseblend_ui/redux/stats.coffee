import { createActions, createReducer } from 'reduxsauce'

import Immutable from 'seamless-immutable'

import { getPointTags } from '~/lib/time'

import config from '~/config'


{ Types, Creators } = createActions(
    enqueueRouteChange: ['url']
    enqueueSidebarAttributeValue: ['attribute', 'value', 'tags']
    enqueueSidebarAttributeOrder: ['attribute', 'order']
    enqueue: ['point']
    dequeue: null
    send: null
    sendImmediately: ['point']
    setAttributesUsage: ['attributesUsage']
    fetchAttributesUsage: null
    sendWs: null
    openWebsocket: ['authToken']
    closeWebsocket: null
, { prefix: 'stats/' })

export { Types as StatsTypes }
export default Creators

export INITIAL_STATE = Immutable(
    queued: []
    sent: []
    attributesUsage: {}
)

setAttributesUsage = (state, { attributesUsage }) -> {
    state...
    attributesUsage
}

enqueue = (state, { point }) -> {
    state...
    queued: [
        state.queued...
        {
            getPointTags()...
            point...
        }
    ]
}

enqueueRouteChange = (state, { url }) -> {
    state...
    queued: [
        state.queued...
        {
            getPointTags()...
            measurement: config.MEASUREMENTS.ROUTE_CHANGE
            fields: { url }
        }
    ]
}

enqueueSidebarAttributeValue = (state, { attribute, value, tags }) -> {
    state...
    queued: [
        state.queued...
        {
            getPointTags(tags)...
            measurement: config.MEASUREMENTS.SIDEBAR_ATTRIBUTE_VALUE
            fields: { "#{ attribute }": value }
        }
    ]
}

enqueueSidebarAttributeOrder = (state, { attribute, order }) -> {
    state...
    queued: [
        state.queued...
        {
            getPointTags()...
            measurement: config.MEASUREMENTS.SIDEBAR_ATTRIBUTE_ORDER
            fields: { "#{ attribute }": order }
        }
    ]
}

dequeue = (state) -> {
    state...
    sent: [
        state.sent...
        state.queued...
    ]
    queued: []
}

sendImmediately = (state, { point }) -> {
    state...
    sent: [
        state.sent...
        {
            getPointTags()...
            point...
        }
    ]
}

ACTION_HANDLERS =
  "#{ Types.ENQUEUE }": enqueue
  "#{ Types.ENQUEUE_ROUTE_CHANGE }": enqueueRouteChange
  "#{ Types.ENQUEUE_SIDEBAR_ATTRIBUTE_VALUE }": enqueueSidebarAttributeValue
  "#{ Types.ENQUEUE_SIDEBAR_ATTRIBUTE_ORDER }": enqueueSidebarAttributeOrder
  "#{ Types.DEQUEUE }": dequeue
  "#{ Types.SEND_IMMEDIATELY }": sendImmediately
  "#{ Types.SET_ATTRIBUTES_USAGE }": setAttributesUsage

export reducer = createReducer(INITIAL_STATE, ACTION_HANDLERS)
