{BufferedProcess} = require('atom')
q = require 'q'
request = require 'request'
tcpPortUsed = require 'tcp-port-used'
log = require './logger'
nodeVersions = require './node-versions'

POLLING_TIMEOUT = 65000 #milliseconds
POLLING_INTERVAL = 1500

TCP_PORT = 8080

truncatePage = (relativeMdPath) ->
  result = relativeMdPath.replace(/\\/g, '/')
  i = result.lastIndexOf('/')
  result = result.substring(0, i)
  if result.startsWith '/'
    result = result.substring(1)
  return result

class RenderingProcessManager
  intervalId: -1
  path: null

  constructor: (@maprDir, @contentDir) ->

  npmInstall: () ->
    deferred = q.defer()

    errors = []
    command = "npm"
    args = ["install"]

    stdout = (output) -> log.debug "npm > #{output}"

    stderr = (output) ->
      stream = log.error
      if output.indexOf('WARN') > 0
        stream = log.debug
      else
        errors.push output

      stream "npm >", output

    exit = (code) ->
      log.debug("npm exited with #{code}")

      if code && code > 0
        deferred.reject message:errors.join "\n"
      if code == 0
        deferred.resolve true

    options =
      cwd: @maprDir
    @npmProcess = new BufferedProcess({command, args, options, stdout, stderr, exit})

    return deferred.promise

  pagePreview: (relativeMdPath) ->
    @path = relativeMdPath
    deferred = q.defer()

    if @alreadyRunning()
      # deferred.reject message: "Rendering process is already running"
      @killPagePreview()

    nodeVersions.checkNodeEnvironment()
      .then () =>
        @npmInstall()
          .then () => @_pagePreview(relativeMdPath)
          .then () -> deferred.resolve true
          .fail (e) =>
            @path = null
            deferred.reject e
      .fail (commands) ->
        msg = "Commands #{commands} not found in your PATH. Please double check it, then reboot." if commands.indexOf('download') < 0
        msg = commands if commands.indexOf('download') >= 0
        path = null
        deferred.reject message: msg

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
        # log.debug "Got line", output
        if !returned && @intervalId<0 && output.trim().startsWith("[metalsmith-serve]")
          @intervalId = window.setInterval () =>
            if pollingStarted < 0
              pollingStarted = new Date().getTime()
            log.debug "Polling http status", requestOpt.url

            now = new Date().getTime()

            if (now - pollingStarted) <= POLLING_TIMEOUT
              request requestOpt, (error, response, body) =>
                code = response && response.statusCode
                log.debug code
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
        log.debug("pagePreview exited with #{code}")
        if code && code > 0 && !returned
          deferred.reject errors.join "\n"

      options =
        cwd: @maprDir

      log.debug "Going to launch", command, args, options
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
    @path = null

  alreadyRunning: () ->
    return @npmProcess? || @pageProcess?

  checkPortInUse: () ->
    return tcpPortUsed.check(TCP_PORT, '127.0.0.1')

module.exports = RenderingProcessManager
