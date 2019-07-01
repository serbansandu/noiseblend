import { init } from "@sentry/browser"
import * as Sentry from "@sentry/browser"

import config from "~/config"

options =
    autoBreadcrumbs: true
    captureUnhandledRejections: true
    release: config.VERSION
    environment:
        if config.DEV
            "development"
        else
            "production"

IsomorphicSentry =
    if process.browser
        init({
            dsn: config.SENTRY_DSN
            options...
        })
        Sentry
    else
        NodeSentry = eval("require('@sentry/node')")
        NodeSentry.init({ dsn: config.SENTRY_DSN, options... })
        NodeSentry

export default IsomorphicSentry
