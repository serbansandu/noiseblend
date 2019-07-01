import React from 'react'
import { connect } from 'react-redux'

import Head from 'next/head'
import Link from 'next/link'

import ImageBackground from '~/components/imageBackground'
import PremiumPrice from '~/components/premiumPrice'
import RoundedButton from '~/components/roundedButton'
import TextButton from '~/components/textButton'

import SpotifyActions from '~/redux/spotify'

import colors from '~/styles/colors'

import config from '~/config'


BuyButton = ({ className, style, id, props... }) ->
    <Link prefetch href='/payment'>
        <a>
            <RoundedButton
                className="py-2 font-heading #{ className ? '' }"
                id={ id }
                textColor={ colors.DARK_MAUVE }
                color={ colors.YELLOW }
                hoverColor={ colors.MAUVE }
                hoverTextColor={ colors.WHITE }
                style={{
                    fontSize: '1.2rem'
                    fontWeight: 500
                    style...
                }}>
                Get Premium
            </RoundedButton>
        </a>
    </Link>

BuyContainer = ({ className, style, id, props... }) ->
    <div
        style={{ style... }}
        id={ id }
        className="flex-column-center #{ className ? '' }">
        <PremiumPrice
            className='my-1'
            color={ colors.DARK_MAUVE }
            size={ 30 } />
        <BuyButton className='my-2' />
    </div>

ShareButton = ({ className, id, style, children, user, setUserDetails, props... }) ->
    <TextButton
        className="
            p-3 font-heading
            share-facebook-button
            #{ className ? '' }"
        id={ id }
        color={ colors.WHITE }
        style={{
            fontSize: 16
            style...
        }}
        onClick={ () -> FB.ui({
            method: 'share',
            display: 'popup',
            href: 'https://www.noiseblend.com',
            hashtag: '#noiseblend'},
            (response) -> checkResponse(response, { user, setUserDetails }))}
        >
        Share on Facebook
    </TextButton>

checkResponse = (response, { user, setUserDetails }) ->
    if not response? or response.error_message
        return
    if not user.sharedAt? and not user.premium
        setUserDetails({ sharedOnSocial: true })


class Premium extends React.Component
    constructor: (props) ->
        super props
        @state =
            fbSdkSrc : null

    @getInitialProps: ({ store, query, res, req, isServer, authenticated, user, api }) ->
        await return {
            initial: {
                background: colors.BLACK
            }
        }

    componentDidMount: ->
        window?.fbAsyncInit ?= () ->
            FB.init({
                appId            : '601429796888451',
                autoLogAppEvents : true,
                xfbml            : true,
                version          : 'v3.0'
            })
        if window?
            @setState
                fbSdkSrc: "https://connect.facebook.net/en_US/sdk.js#xfbml=1&version=v3.0"

    render: ->
        <div className='fill-window flex-column-center' id='page-container'>
            <Head>
                <script src={ @state.fbSdkSrc }></script>
            </Head>
            <div id="top-part" style={ position: 'relative' }>
                <div className='video-bg-container'>
                    <video
                        className='blend-demo-bg'
                        autoPlay={true}
                        playsInline={true}
                        muted={true}
                        loop={true}>
                        <source
                            src="#{ config.STATIC }/video/blend-demo-blurred.mp4?v=3"
                            type='video/mp4' />
                    </video>
                </div>
                <div id="top-part-content">
                    <div className='d-flex flex-column blend-feature'>
                        <div className='
                            fill-width flex-column-center flex-lg-row justify-content-around
                            feature-container blend-video-container'>
                            <div className='feature-description text-center text-lg-left'>
                                <h1 className='mb-3 text-dark'>
                                    Blends
                                </h1>
                                <h5 className='text-dark'>
                                    One-tap music for every occasion
                                </h5>
                            </div>
                            <video
                                className='video-demo blend-demo'
                                autoPlay={true}
                                playsInline={true}
                                muted={true}
                                loop={true}>
                                <source
                                    src="#{ config.STATIC }/video/blend-demo.mp4?v=3"
                                    type='video/mp4' />
                            </video>
                        </div>
                    </div>
                </div>
            </div>
            <div
                id='bottom-part'
                className='
                    fill-width flex-column-center
                    justify-content-center justify-content-lg-around
                    flex-lg-row-reverse feature-container explicit-video-container'>
                <div className='feature-description text-center text-lg-left'>
                    <h1 className='mb-3 mt-5 mt-lg-0 text-light'>
                        Explicit Filter
                    </h1>
                    <h5 className='text-light'>
                        For when kids are around
                    </h5>
                </div>
                <video
                    className='video-demo explicit-demo'
                    autoPlay={true}
                    playsInline={true}
                    muted={true}
                    loop={true}>
                    <source
                        src="#{ config.STATIC }/video/explicit-demo.mp4"
                        type='video/mp4' />
                </video>
            </div>
            <div className='fill-width flex-center' id="share-fb-container">
                <ShareButton
                    setUserDetails={ @props.setUserDetails }
                    user={ @props.user }
                    className='share-fb-button'
                />
            </div>
            <style jsx>{"""#{} // stylus
                #page-container
                    position relative

                    #share-fb-container
                        absolute bottom left
                        :global(.share-fb-button)
                            color facebookF
                            background-color white
                            border-radius top 7px
                            padding 5px

                    #top-part
                        #top-part-content
                            background-color alpha(flashWhite, 80%)
                            position relative
                            z-index 1

                        .video-bg-container
                            overflow hidden
                            height 100%
                            absolute top left

                            .blend-demo-bg
                                min-width 100vw
                                min-height 100%

                    .feature-description
                        @media (max-width: $mobile)
                            max-width 80vw

                    .feature-container
                        padding-top 60px
                        padding-bottom 60px
                        @media (max-width: $mobile)
                            padding-top 20px
                            padding-bottom 20px

                        &.explicit-video-container
                            background-color #1A191B
                            padding-bottom 100px

                        .video-demo
                            height 40vh
                            max-width 548px
                            border-radius 20px
                            background-color black

                            @media (max-width: $mobile)
                                height initial
                                max-width 70vw
                                border-radius 10px
                                margin-top 30px
                                margin-bottom 50px

                        .blend-demo
                            background-color transparent
            """}</style>
        </div>

mapStateToProps = (state) ->
    user: state.spotify.user

mapDispatchToProps = (dispatch) ->
    setUserDetails: (details) -> dispatch(SpotifyActions.setUserDetails(details))

export default connect(mapStateToProps, mapDispatchToProps)(Premium)
