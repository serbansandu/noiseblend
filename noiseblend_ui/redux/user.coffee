import { createActions, createReducer } from 'reduxsauce'

import Immutable from 'seamless-immutable'

import config from '~/config'
import '~/lib/str'

{ Types, Creators } = createActions(
    fetchDislikes: ['key']
    invalidateDislikes: null
    setDislikes: ['key', 'items']
    finishFetchingDislikes: null
    removeDislike: ['key', 'item']
    addDislike: ['key', 'item']
    checkout: ['nonce']
    finishCheckout: ['ok']
, { prefix: 'user/' })

export UserTypes = Types
export default Creators


export INITIAL_STATE = Immutable(
    dislikedArtists: []
    dislikedGenres: []
    dislikedCities: []
    dislikedCountries: []
    fetching: true
    fetchedDislikes: false
    checkingOut: false
    boughtPremium: false
)

getIdKey = (itemType) ->
    switch itemType
        when 'artists' then 'id'
        when 'countries' then 'code'
        else 'name'


setDislikes = (state, { key, items }) -> {
    state...
    "disliked#{ key.toTitleCase() }": items
}

addDislike = (state, { key, item }) -> {
    state...
    "disliked#{ key.toTitleCase() }": [
        state["disliked#{ key.toTitleCase() }"]...
        (if Array.isArray(item) then item else [item])...
    ]
}

removeDislike = (state, { key, item }) ->
    idKey = getIdKey(key)
    items = if Array.isArray(item)
        (i[idKey] for i in item)
    else
        [item[idKey]]
    {
        state...
        "disliked#{ key.toTitleCase() }": state["disliked#{ key.toTitleCase() }"].filter(
            (oldItem) -> oldItem[idKey] not in items
        )
    }

fetchDislikes = (state) -> {
    state...
    fetching: true
}

invalidateDislikes = (state) -> {
    state...
    fetchedDislikes: false
}

finishFetchingDislikes = (state) -> {
    state...
    fetching: false
    fetchedDislikes: true
}

checkout = (state) -> {
    state...
    checkingOut: true
}

finishCheckout = (state, { ok }) -> {
    state...
    checkingOut: false
    boughtPremium: ok
}

ACTION_HANDLERS =
    "#{ Types.SET_DISLIKES }": setDislikes
    "#{ Types.FETCH_DISLIKES }": fetchDislikes
    "#{ Types.INVALIDATE_DISLIKES }": invalidateDislikes
    "#{ Types.FINISH_FETCHING_DISLIKES }": finishFetchingDislikes
    "#{ Types.REMOVE_DISLIKE }": removeDislike
    "#{ Types.ADD_DISLIKE }": addDislike
    "#{ Types.CHECKOUT }": checkout
    "#{ Types.FINISH_CHECKOUT }": finishCheckout


export reducer = createReducer(INITIAL_STATE, ACTION_HANDLERS)
