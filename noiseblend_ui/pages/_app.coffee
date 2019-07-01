import '~/lib/util'

import React from "react"
import { connect } from 'react-redux'
import { Provider } from "react-redux"

import anime from 'animejs'
import _ from 'lodash'
import withRedux from "next-redux-wrapper"
import Head from 'next/head'
import Router from 'next/router'

import App, { Container } from "next/app"

import AppleLaunchScreenLinks from '~/components/appleLaunchScreenLinks'
import DonateView from '~/components/donateView'
import Layout from '~/components/layout'
import RoundedButton from '~/components/roundedButton'

import redirect from '~/lib/redirect'
import Sentry from '~/lib/sentry'
import { randomInt } from '~/lib/util'

import createStore from '~/redux'
import AuthActions from '~/redux/auth'
import SpotifyActions from '~/redux/spotify'
import StatsActions from '~/redux/stats'
import UIActions from '~/redux/ui'

import API from '~/services/api'

import colors from '~/styles/colors'

import config from '~/config'


AsyncMode = React.unstable_AsyncMode

showDonateButton = () ->
    anime.timeline(elasticity: 400).add(
        targets: '#donate-view'
        translateX: 0
        duration: 100
    ).add(
        targets: '#donate-view #bmac-link'
        translateX: [300, 0]
    ).add(
        targets: ['#donate-view .bmac-description', '#donate-view #bmac-hide']
        offset: 200
        translateX: [300, 0]
    ).add(
        targets: '#donate-view .bmac-description .underline'
        offset: '-=600'
        delay: (el, i) -> i * 300
        width: ['0%', '104%']
        easing: 'easeInOutExpo'
        duration: 600
    ).add(
        targets: '#donate-view #bmac-hide'
        offset: 4500
        opacity: [0, 1]
    )

hideDonateButton = () ->
    anime.timeline().add(
        targets: '#donate-view'
        opacity: [1, 0]
        easing: 'easeInOutCubic'
        duration: 1500
    ).add(
        targets: '#donate-view'
        translateX: 300
        duration: 100
    )


class MyApp extends App
    constructor: (props) ->
        super props
        @detectMobileDeferred = _.debounce(
            (() => @detectMobile()),
            config.POLLING.WINDOW_RESIZE)
        @statsSender = null

        @onRouteChangeComplete = null
        @onRouteChangeStart = null
        @onRouteChangeError = null

        @loadingSetter = null
        @driftWatcher = null
        @driftWatcherTimeout = null

    @getInitialProps: ({ Component, router, ctx }) ->
        { store, query, res, req, ctx... } = ctx
        isServer = req?
        cache = if isServer then req?.cache else null
        blendToken = query.blendToken

        api = API.create({ isServer, store, query, res, req, blendToken, cache })

        authenticated = false
        user = store.getState().spotify?.user
        if user?
            authenticated = true
        else
            authenticatedRes = await api.isAuthenticated()
            if authenticatedRes.ok
                authenticated = authenticatedRes.data.authenticated
            else
                { problem, data, sentryEventId } = authenticatedRes
                await return { error: { problem, data, sentryEventId } }

            isUnauthorizedPage = router.route in config.UNAUTHORIZED_PAGES
            isStaticRoute = router.route.match(/\/static\/.+/)?

            if authenticated is true
                userRes = await api.getUserDetails()
                if not userRes.ok
                    { problem, data, sentryEventId } = userRes
                    await return { error: { problem, data, sentryEventId } }
            else if not isUnauthorizedPage or not isStaticRoute
                redirect({target: '/', res, isServer})
                await return {}

            user = userRes?.data

        ctx = { store, query, res, req, authenticated, user, isServer, api, ctx... }
        pageProps = {}
        if Component.getInitialProps
            pageProps = await Component.getInitialProps(ctx) ? {}

        if pageProps.error?.problem?
            { problem, data, sentryEventId } = pageProps.error
            pageProps = {
                pageProps...
                error: { problem, data, sentryEventId }
            }

        fetchedProps = {
            user: user
            authToken: api.getAuthToken()
            (pageProps.fetched ? {})...
        }

        initialProps = {
            config.DEFAULT_PAGE_PROPS...
            (config.PAGE_PROPS[router.route] ? {})...
            (pageProps.initial ? {})...
        }

        return {
            authenticated
            pageProps...
            fetched: fetchedProps
            initial: initialProps
        }

    detectMobile: ->
        @props.batchActions([
            UIActions.setWindowWidth(window.innerWidth)
            UIActions.setMobile(window.innerWidth <= config.WIDTH.mobile)
            UIActions.setMediumScreen(window.innerWidth <= config.WIDTH.medium)
        ])
        @handleDriftWidget()

    componendDidCatch: (error, info) ->
        Sentry.configureScope((scope) ->
            scope.setExtra(errorInfo: JSON.stringify(info)))
        Sentry.captureException(error)

    componentWillUnmount: ->
        if @statsSender?
            clearInterval(@statsSender)

        @stopDriftWatcher()
        @stopDriftWatcherTimeout()

        window.removeEventListener('resize', @detectMobileDeferred)
        Router.events.off("routeChangeComplete", @onRouteChangeComplete)
        Router.events.off("routeChangeStart", @onRouteChangeStart)
        Router.events.off("routeChangeError", @onRouteChangeError)

    componentDidUpdate: (prevProps, prevState, snapshot) ->
        prevUser = prevProps.fetched?.user
        user = @props.fetched?.user
        if user? and user.lastFetch > (prevUser?.lastFetch ? 0) and
        not _.isEqual(prevUser, user)
            @props.setUser(user)

    componentDidMount: ->
        if @props.user?
            return

        if @props.authenticated and not @props.blendParams?
            @props.openStatsWebsocket(@props.fetched?.authToken)

        @statsSender ?= setInterval(
            (() =>
                if @props.authenticated
                    @props.sendStats()
            ),
            config.POLLING.STATS_SENDER
        )

        @detectMobile()
        window.addEventListener('resize', @detectMobileDeferred)

        @addRouteEventListeners()
        @loadDrift()
        # @loadHotjar()
        # @loadTagManager()

        if @props.error
            @props.setErrorMessage(@props.error)
            return

        actions = [
            UIActions.setState(@props.initial)
            AuthActions.setAuthenticated(@props.authenticated)
        ]
        if @props.fetched?.authToken?
            actions.push(AuthActions.setAuthToken(@props.fetched.authToken))

        if @props.fetched?.user?
            user = @props.fetched.user
            actions.push(SpotifyActions.setUser(user))
            mediumUsage = not (
                user.firstPlay and
                user.firstBlend and
                user.firstDislike and
                user.secondPlaylist
            )
            if not user.donateButtonHidden and mediumUsage
                setTimeout(showDonateButton, randomInt(5, 60) * config.POLLING.DONATE_BUTTON)

        @props.batchActions(actions)

    handleDriftWidget: (pathname) ->
        pathname ?= Router.pathname
        if @props.blendParams? or
        (pathname isnt '/' and window.innerWidth <= config.WIDTH.mobile)
            drift?.api?.widget?.hide?()
        else if not @props.blendParams?
            drift?.api?.widget?.show?()

    addRouteEventListeners: ->
        @onRouteChangeError = (err, url) =>
            @props.setUIState({
                circularMenuOpen: false
                loading: false
            })

            if @loadingSetter?
                clearTimeout(@loadingSetter)

        @onRouteChangeComplete = (url) =>
            pathname = url.match(config.PATHNAME_PATTERN)?[0]
            pageProps = config.PAGE_PROPS[pathname] ? {}
            @props.batchActions([
                StatsActions.enqueueRouteChange(url)
                UIActions.setState({
                    config.DEFAULT_PAGE_PROPS...
                    pageProps...
                    loading: false
                })
            ])

            if @loadingSetter?
                clearTimeout(@loadingSetter)

            @handleDriftWidget(pathname)

        @onRouteChangeStart = (url) =>
            if Router.pathname is '/blend' and url isnt '/blend'
                window.location.href = url

            @props.setUIState({
                circularMenuOpen: false
                loading: true
            })

            if @loadingSetter?
                clearTimeout(@loadingSetter)
            @loadingSetter = setTimeout((() => @props.setUIState(loading: false)), 10000)


        Router.events.on("routeChangeError", @onRouteChangeError)
        Router.events.on("routeChangeComplete", @onRouteChangeComplete)
        Router.events.on("routeChangeStart", @onRouteChangeStart)

    loadTagManager: ->
        window.l ?= []
        window.l.push({
            'gtm.start': new Date().getTime(),
            event: 'gtm.js'
        })
        f = document.getElementsByTagName('script')[0]
        j = document.createElement('script')
        j.async = true
        j.src = 'https://www.googletagmanager.com/gtm.js?id=GTM-PJWKF7J'
        f.parentNode.insertBefore(j, f)

    loadHotjar: ->
        window.hj ?= () ->
            window.hj.q ?= []
            window.hj.q.push(arguments)

        window._hjSettings =
            hjid: if config.PRODUCTION then 912982 else 913519
            hjsv: 6

        head = document.getElementsByTagName('head')[0]
        scriptElement = document.createElement('script')
        scriptElement.async = 1
        scriptElement.src = "
            https://static.hotjar.com/c/hotjar-\
            #{ window._hjSettings.hjid }.js?\
            sv=#{ window._hjSettings.hjsv }"
        head.appendChild(scriptElement)

    loadDrift: ->
        @driftWatcher = setInterval(
            (() =>
                if not window.drift?
                    return
                @stopDriftWatcher()
                @stopDriftWatcherTimeout()
                @initDrift()
            ), 100
        )
        @driftWatcherTimeout = setTimeout(
            (() =>
                @stopDriftWatcher()
                @driftWatcherTimeout = null
            ), 20000
        )

        t = window.driftt = window.drift = window.driftt or []
        if not t.init
            if t.invoked
                console.error("Drift snippet included twice.")
                return
            t.invoked = true
            t.methods = [
                "identify", "config", "track", "reset",
                "debug", "show", "ping", "page",
                "hide", "off", "on",
            ]
            t.factory = (e) ->
                return () ->
                    n = Array.prototype.slice.call(arguments)
                    n.unshift(e)
                    t.push(n)
                    return t
            t.methods.forEach((e) -> t[e] = t.factory(e))
            t.load = (t) ->
                e = 3e5
                n = Math.ceil(new Date() / e) * e
                o = document.createElement("script")
                o.type = "text/javascript"
                o.async = true
                o.crossorigin = "anonymous"
                o.src = "https://js.driftt.com/include/#{ n }/#{ t }.js"
                i = document.getElementsByTagName("script")[0]
                i.parentNode.insertBefore(o, i)

        drift.SNIPPET_VERSION = '0.3.1'
        drift.load('n2mza8kkuvk6')


    initDrift: ->
        @hideMessage = () =>
            if @props.authenticated
                @props.setUserDetails(driftMessageHidden: true)
            drift.off('welcomeMessage:close', @hideMessage)
            drift.off('awayMessage:close', @hideMessage)

        drift.on('ready', (api) =>
            if @props.authenticated
                @handleDriftWidget()
                user = @props.user ? @props.fetched?.user
                if user? and not user?.driftMessageHidden
                    drift.on('welcomeMessage:close', @hideMessage)
                    drift.on('awayMessage:close', @hideMessage)
                    if not @props.blendParams?
                        api.showWelcomeOrAwayMessage()
        )

    stopDriftWatcher: ->
        if @driftWatcher?
            clearInterval(@driftWatcher)
            @driftWatcher = null

    stopDriftWatcherTimeout: ->
        if @driftWatcherTimeout?
            clearTimeout(@driftWatcherTimeout)
            @driftWatcherTimeout = null

    render: ->
        { Component, store, props... } = @props
        defaultPageProps = config.DEFAULT_PAGE_PROPS
        icon = props.icon ? props.initial?.icon ? defaultPageProps.icon
        color = "#{ props.color ? props.initial?.color ? defaultPageProps.color }"
        title = props.title ? props.initial?.title ? defaultPageProps.title
        description = (
            props.description ?
            props.initial?.description ?
            defaultPageProps.description
        )
        spotifyPremium = props.user?.spotifyPremium ? props.fetched?.user?.spotifyPremium
        manifest = props.manifest ? props.initial?.manifest ? defaultPageProps.manifest

        <AsyncMode>
            <Container>
                <Provider store={ store }>
                    <Layout
                        authenticated={ props.authenticated }
                        spotifyPremium={ spotifyPremium }
                        fillWindow>
                        <Head>
                            <title> { title ? 'Noiseblend' } </title>
                            <meta name="description" content={ description } />
                            <meta name="theme-color" content={ color } />
                            <meta
                                name="msapplication-TileColor"
                                content={ color } />
                            <meta
                                name="msapplication-TileImage"
                                content="
                                    #{ config.STATIC }/img/icons/\
                                    #{ icon }/#{ icon }\
                                    -apple-144x144.png\
                                    ?v=#{ config.ICON_VERSION }" />
                            <link href={ manifest } rel='manifest' />
                            {
                                links = for platform, sizes of config.ICONS
                                    for size in sizes
                                        <link
                                            key="#{ platform }-#{ size }"
                                            rel={if platform is 'apple'
                                                'apple-touch-icon'
                                            else
                                                'icon'
                                            }
                                            sizes="#{ size }x#{ size }"
                                            href="
                                                #{ config.STATIC }/img/icons/\
                                                #{ icon }/#{ icon }-#{ platform }-\
                                                #{ size }x#{ size }.png\
                                                ?v=#{ config.ICON_VERSION }" />
                                links.reduce((acc, v) -> acc.concat(v))
                            }
                            <AppleLaunchScreenLinks topic={ icon } />
                            <noscript
                                dangerouslySetInnerHTML={
                                    __html: '<iframe
                                                src="https://www.googletagmanager.com/ns.html?id=GTM-PJWKF7J"
                                                height="0" width="0"
                                                style="display:none;visibility:hidden">
                                            </iframe>'
                            } />
                        </Head>
                        <DonateView onClick={ hideDonateButton } id='donate-view' />
                        <Component { props... } />
                        <style global jsx>{"""#{} // stylus
                            #donate-view
                                fixed bottom 20vh right 20px
                                transform translateX(300px)
                                z-index 3

                                #bmac-link
                                .bmac-description
                                #bmac-hide
                                    transform translateX(300px)

                                #bmac-hide
                                    opacity 0
                        """}</style>
                    </Layout>
                </Provider>
            </Container>
        </AsyncMode>



mapStateToProps = ({ ui, auth, spotify }) ->
    authToken    : auth.authToken
    color        : ui.color
    description  : ui.description
    errorMessage : spotify.errorMessage
    icon         : ui.icon
    manifest     : ui.manifest
    mobile       : ui.mobile
    sentryEventId: spotify.sentryEventId
    title        : ui.title
    user         : spotify.user

mapDispatchToProps = (dispatch) ->
    batchActions: (actions) -> dispatch(actions)
    setErrorMessage: (error) -> dispatch(SpotifyActions.setErrorMessage(error))
    setUser: (user) -> dispatch(SpotifyActions.setUser(user))
    setUserDetails: (details) -> dispatch(SpotifyActions.setUserDetails(details))
    setUIState: (ui) -> dispatch(UIActions.setState(ui))
    sendStats: () -> dispatch(StatsActions.sendWs())
    openStatsWebsocket: (authToken) -> dispatch(StatsActions.openWebsocket(authToken))
    setCircularMenuOpen: (open) -> dispatch(UIActions.setCircularMenuOpen(open))


export default withRedux(
    createStore
    debug: config.REDUX_DEBUG
)(connect(mapStateToProps, mapDispatchToProps)(MyApp))
