{BufferedProcess} = require('atom')
q = require 'q'
request = require 'request'
POLLING_TIMEOUT = 45000 #milliseconds
POLLING_INTERVAL = 1500

truncatePage = (relativeMdPath) ->
  relativeMdPath = relativeMdPath.replace(/\\/g, '/')
  i = relativeMdPath.lastIndexOf('/')
  relativeMdPath = relativeMdPath.substring(0, i)
  if relativeMdPath.startsWith '/'
    relativeMdPath = relativeMdPath.substring(1)
  return relativeMdPath

class RenderingProcessManager
  intervalId: -1

  constructor: (@maprDir, @contentDir) ->

  npmInstall: () ->
    deferred = q.defer()

    errors = []
    command = "npm"
    args = ["install"]

    stdout = (output) -> console.log "npm >", output

    stderr = (output) ->
      console.error "npm >", output
      errors.push output

    exit = (code) ->
      console.log("npm exited with #{code}")

      if code && code > 0
        deferred.reject message:errors.join "\n"
      if code == 0
        deferred.resolve true

    options =
      cwd: @maprDir
    @npmProcess = new BufferedProcess({command, args, options, stdout, stderr, exit})

    return deferred.promise

  pagePreview: (relativeMdPath) ->
    deferred = q.defer()

    if @pageProcess?
      deferred.reject message: "Rendering process is already running"
    else
      @checkNodeEnvironment()
        .then () =>
          @npmInstall()
            .then () => @_pagePreview(relativeMdPath)
            .then () -> deferred.resolve true
            .fail (e) -> deferred.reject e
        .fail (commands) ->
          deferred.reject message: "Commands #{commands} not found in your PATH. Please double check it, then reboot."

    return deferred.promise

  _pagePreview: (relativeMdPath) ->
    deferred = q.defer()
    returned = false
    errors = []
    @intervalId = -1
    pollingStarted = -1

    noTrailingSlashPath = truncatePage(relativeMdPath)
    noTrailingSlashPath = relativeMdPath.substring(1) if noTrailingSlashPath.startsWith '/'

    if @pageProcess?
      deferred.reject message: "Rendering process is already running"
    else
      requestOpt =
        url: "http://localhost:8080/" + noTrailingSlashPath
        proxy: null

      command = "node"

      filePath = relativeMdPath
      if relativeMdPath.startsWith('\\') || relativeMdPath.startsWith('/')
        filePath = relativeMdPath.substring(1)

      args = ["preview.js", "#{filePath}", "#{@contentDir}"]
      stdout = (output) =>
        # console.log "Got line", output
        if !returned && @intervalId<0 && output.trim().startsWith("[metalsmith-serve]")
          @intervalId = window.setInterval () =>
            if pollingStarted < 0
              pollingStarted = new Date().getTime()
            console.log "Polling http status", requestOpt.url

            now = new Date().getTime()

            if (now - pollingStarted) <= POLLING_TIMEOUT
              request requestOpt, (error, response, body) =>
                code = response && response.statusCode
                console.log code
                if code == 200 && !returned
                  returned = true
                  @clearInterval()
                  deferred.resolve true
            else if !returned
              returned = true
              @killPagePreview()
              deferred.reject message: "Preview process took too much to respond"
          , POLLING_INTERVAL
      stderr = (output) ->
        console.error output
        errors.push output
      exit = (code) ->
        console.log("pagePreview exited with #{code}")
        if code && code > 0 && !returned
          deferred.reject errors.join "\n"

      options =
        cwd: @maprDir

      console.log "Going to launch", command, args, options
      @pageProcess = new BufferedProcess({command, args, options, stdout, stderr, exit})

    return deferred.promise

  clearInterval: () ->
    window.clearInterval @intervalId if @intervalId > 0
    @intervalId = -1

  killPagePreview: () ->
    @clearInterval()
    @npmProcess?.kill()
    @pageProcess?.kill()
    @pageProcess = null
    @npmProcess = null

  checkNodeEnvironment: () ->
    deferred = q.defer()
    q.all([@_which("npm"), @_which("node")])
      .then (commands) ->
        filtered = commands.filter (x) -> x
        if filtered.length == 0
          deferred.resolve true
        else
          deferred.reject commands.join ', '
    return deferred.promise

  _which: (command) ->
    deferred = q.defer()
    which = require 'which'

    which command, (err, result) ->
      if err
        deferred.resolve command
      else
        deferred.resolve null

    return deferred.promise


module.exports = RenderingProcessManager
