import React from 'react'

class TrialCountdown extends React.Component
    constructor: (props) ->
        super props
        @timeUpdater = null
        @state =
            initialTimeRemaining: props.timeRemaining
            timeRemaining: props.timeRemaining

    @getDerivedStateFromProps: (nextProps, prevState) ->
        if nextProps.timeRemaining isnt prevState.initialTimeRemaining
            return {
                initialTimeRemaining: nextProps.timeRemaining,
                timeRemaining: nextProps.timeRemaining
            }
        return null

    componentWillUnmount: ->
        if @timeUpdater?
            clearInterval(@timeUpdater)

    componentDidMount: ->
        if @isInTrial()
            @startTimeUpdater()

    startTimeUpdater: ->
        if @timeUpdater?
            clearInterval(@timeUpdater)
        @timeUpdater = setInterval(
            (() =>
                if @state.timeRemaining <= 0
                    clearInterval(@timeUpdater)
                    @timeUpdater = null
                @setState(timeRemaining: @state.timeRemaining - 1)),
                1000
        )

    componentDidUpdate: (prevProps, prevState, snapshot) ->
        if prevState.initialTimeRemaining isnt @state.initialTimeRemaining and
        @state.initialTimeRemaining?
            @startTimeUpdater()

    leftPad: (value) ->
        if value < 10 then "0#{ value }" else "#{ value }"

    isInTrial: ->
        not @props.user?.premium and
        (@props.user?.isInTrial or @props.user?.didShareOnSocial)

    getRemainingTrialTime: ->
        if not @isInTrial()
            return ""
        if not @state.timeRemaining? or @state.timeRemaining <= 0
            return ""

        daysRemaining = Math.floor(@state.timeRemaining / 86400)
        timeRemaining = @state.timeRemaining - (daysRemaining * 86400)
        hoursRemaining = Math.floor( timeRemaining / 3600 )
        timeRemaining = timeRemaining - (hoursRemaining * 3600)
        minutesRemaining =  Math.floor( timeRemaining / 60 )
        timeRemaining = timeRemaining - (minutesRemaining * 60)
        secondsRemaining = timeRemaining
        timeRemainingString = "
            #{ @leftPad(minutesRemaining) } :
            #{ @leftPad(secondsRemaining) }"
        if hoursRemaining or daysRemaining
            timeRemainingString = "
            #{ @leftPad(hoursRemaining) } :
            #{ @leftPad(timeRemainingString) }"
        if daysRemaining
            timeRemainingString = "
            #{ @leftPad(daysRemaining) } :
            #{ @leftPad(timeRemainingString) }"
        return timeRemainingString

    render: ->
        remainingTrial = @getRemainingTrialTime()
        <div
            className="trial-timer #{ @props.className ? '' }"
            id={ @props.id ? '' }
            style={
                @props.style
            }>
            <div className='remaining-text'>
                {if remainingTrial?.length > 0
                    'Remaining Trial'
                else
                    'Trial Ended'
                }
            </div>
            { remainingTrial }
        <style jsx>{"""#{} // stylus
            .trial-timer
                color mix(red, magenta)
            .remaining-text
                color darkGray
        """}</style>
        </div>

export default TrialCountdown
