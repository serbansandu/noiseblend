import { connect } from 'react-redux'

import Link from 'next/link'

import CloseButton from '~/components/closeButton'
import PremiumPrice from '~/components/premiumPrice'
import TextButton from '~/components/textButton'

import colors from '~/styles/colors'

import config from '~/config'

PremiumDialog = ({ visible, props... }) ->
    <div
        className='premium-dialog'
        style={
            visibility: if visible then 'visible' else 'hidden'
            opacity: if visible then 1 else 0
        }>
        <CloseButton
            id='close-device-drawer-button'
            circle={ false }
            style={ position: 'absolute' }
            onClose={ () -> props.closePremiumDialog() }
            color={ colors.PITCH_BLACK }
            strokeWidth={ 3 }
            size={ 20 }
        />
        <Link prefetch href='/premium'>
            <a className='w-100'>
                <TextButton
                    className='w-100'
                    id='get-premium-button'
                    color={ colors.WHITE.mix(colors.YELLOW, 0.2) }>
                    <div className='message'>
                        <h4
                            style={
                                lineHeight: 1.3
                            }
                            className='px-4 text-dark'>
                            Seems like you really need this Premium feature
                        </h4>
                        <h5 style={
                            color: colors.RED
                        }>
                            Explicit Filter
                        </h5>
                    </div>
                    <span>
                        Get Premium
                        <PremiumPrice
                            color={ colors.DARK_MAUVE.darken(0.1) }
                            slashColor={ colors.WHITE.mix(colors.YELLOW, 0.5) } />
                    </span>
                </TextButton>
            </a>
        </Link>
        <TextButton
            id='skip-premium-button'
            className='w-100 py-3'
            color={ colors.BLACK.alpha(0.5) }
            onClick={ props.continueAction }>
            Disable Explicit Filter
        </TextButton>
        <style global jsx>{"""#{} // stylus
            width = 500px
            height = width / 2
            #get-premium-button
                font-weight 700
                font-size 2.5rem
                height 80%
                &:hover
                    background-color yellow + 20%
                    filter: none

                @media (max-width: width)
                    height 90%

            #skip-premium-button
                box-shadow inset 0 7px 13px alpha(black, 0.2)
                font-size 0.9rem
                border-radius 0px 0px 8px 8px
                background-color mix(yellow, white, 70%)
                height 20%

                @media (max-width: width)
                    border-radius 0
                    height 10%
        """}</style>
        <style jsx>{"""#{} // stylus
            width = 700px
            height = width / 2
            .premium-dialog
                center width height fixed
                width width
                height height
                border-radius 8px
                background-color yellow

                transition:
                    visibility 0.05s linear,
                    opacity 0.5s easeOutCubic 0.05s

                @media (max-width: width)
                    width 100vw
                    height 100vh
                    fixed top left
                    border-radius 0

                .message
                    margin-bottom: 5%
                    @media (max-width: width)
                        margin-top: -15vh
                        margin-bottom: 20vh
        """}</style>
    </div>

mapStateToProps = (state) ->
    user: state.spotify.user

mapDispatchToProps = (dispatch) ->
    batchActions: (actions) -> dispatch(actions)


export default connect(mapStateToProps, mapDispatchToProps)(PremiumDialog)
