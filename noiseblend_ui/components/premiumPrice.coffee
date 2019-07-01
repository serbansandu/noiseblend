import { connect } from 'react-redux'

import colors from '~/styles/colors'

import config from '~/config'



PremiumPrice = ({
    className, id, style, children, color = colors.WHITE,
    slashColor, user, batchActions, size = 20, slashSize, props...
}) ->
    discount = false
    price = config.DEFAULTS.PREMIUM_PRICE
    userPrice = user?.premiumPrice
    if userPrice? and userPrice < price
        discount = true

    <h6
        className="
            d-flex justify-content-center align-items-center
            #{ className ? '' }"
        id={ id ? '' }
        style={ style }
        { props... }>
        <span style={
            color: color
            fontSize: size
        }>${ userPrice ? price }</span>
        {if discount
            <sup>
                <span className="strikethrough">
                    { price }
                </span>
            </sup>
        }
        <svg
            xmlns="http://www.w3.org/2000/svg"
            width={ slashSize ? size + 2 }
            height={ slashSize ? size + 2 }
            viewBox="0 0 24 24"
            fill="none"
            stroke={ slashColor ? color }
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round">
            <line x1="14" y1="0" x2="10" y2="24" />
        </svg>
        <span style={
            color: color
            fontSize: size
        }>lifetime</span>
        <style jsx>{"""#{} // stylus
            .strikethrough
                position relative
                color red

            .strikethrough:before
                position absolute
                content ""
                left 0
                top 50%
                right 0
                border-top 1px solid
                border-color inherit

                transform rotate(-5deg)
        """}</style>
    </h6>

mapStateToProps = (state) ->
    user: state.spotify.user

mapDispatchToProps = (dispatch) ->
    batchActions: (actions) -> dispatch(actions)


export default connect(mapStateToProps, mapDispatchToProps)(PremiumPrice)
