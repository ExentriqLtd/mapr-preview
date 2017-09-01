{BufferedProcess} = require('atom')
q = require 'q'
request = require 'request'
POLLING_TIMEOUT = 30000 #milliseconds

truncatePage = (relativeMdPath) ->
  i = relativeMdPath.lastIndexOf('/')
  return relativeMdPath.substring(0, i)

class RenderingProcessManager

  constructor: (@maprDir, @contentDir) ->
    console.log @maprDir, @contentDir

  pagePreview: (relativeMdPath) ->
    deferred = q.defer()
    returned = false
    errors = []
    intervalId = -1
    pollingStarted = -1
    if @pageProcess?
      deferred.reject message: "Rendering process is already running"
    else
      requestOpt =
        url: "http://localhost:8080/" + truncatePage(relativeMdPath)
        proxy: null

      command = "node"
      args = ["preview.js", "#{relativeMdPath}", "#{@contentDir}"]
      stdout = (output) =>
        # console.log "Got line", output
        if !returned && intervalId<0 && output.trim().startsWith("[metalsmith-serve]")
          intervalId = window.setInterval () =>
            if pollingStarted < 0
              pollingStarted = new Date().getTime()
            console.log "Polling http status", requestOpt.url

            now = new Date().getTime()

            if (now - pollingStarted) <= POLLING_TIMEOUT
              request requestOpt, (error, response, body) ->
                code = response && response.statusCode
                console.log code
                if code == 200 && !returned
                  returned = true
                  window.clearInterval intervalId
                  deferred.resolve true
            else if !returned
              returned = true
              window.clearInterval intervalId
              @killPagePreview()
              deferred.reject message: "Preview process took too much to respond"
          , 1500
      stderr = (output) ->
        console.error output
        errors.push output
      exit = (code) ->
        console.log("pagePreview exited with #{code}")
        if code && code > 0 && !returned
          deferred.reject errors.join "\n"

      options =
        cwd: @maprDir
      @pageProcess = new BufferedProcess({command, args, options, stdout, stderr, exit})

    return deferred.promise

  killPagePreview: () ->
    @pageProcess?.kill()
    @pageProcess = null

module.exports = RenderingProcessManager
