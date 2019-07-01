import apisaucePlugin from 'reactotron-apisauce'
import Reactotron, { trackGlobalErrors } from 'reactotron-react-js'
import { reactotronRedux } from 'reactotron-redux'
import sagaPlugin from 'reactotron-redux-saga'

import _ from 'lodash'
import Immutable from 'seamless-immutable'

import StartupTypes from '~/redux/startup'
import StatsTypes from '~/redux/stats'

import config from '~/config'


if config.DEBUG and not config.DISABLE_REACTOTRON
    Reactotron
        .configure(name: 'Noiseblend')
        # .use(trackGlobalErrors(
        #     veto: (frame) -> 'node_modules/next' not in frame.fileName
        # ))
        .use(apisaucePlugin())
        .use(reactotronRedux({
            except: [StatsTypes.SEND]
            isActionImportant: (action) -> action.type is StartupTypes.STARTUP
            onRestore: (state) -> Immutable(state)
        }))
        .use(sagaPlugin())
        .connect()

    Reactotron.clear()
    console.tron = Reactotron
    console.tron.debug = _.partialRight(console.tron.debug, true)
    console.tron.warn = _.partialRight(console.tron.warn, true)
    console.tron.error = _.partialRight(console.tron.error, true)
    console.tron.image = _.partialRight(console.tron.image)
else
    console.tron =
        log: () -> false
        logImportant: () -> false
        debug: () -> false
        warn: () -> false
        error: () -> false
        display: () -> false
        image: () -> false
