{BufferedProcess} = require('atom')
q = require 'q'
request = require 'request'
tcpPortUsed = require 'tcp-port-used'

POLLING_TIMEOUT = 65000 #milliseconds
POLLING_INTERVAL = 1500

TCP_PORT = 8080

NODE_VERSION = major: 6, minor: 5
NPM_VERSION = major: 3, minor: 8

truncatePage = (relativeMdPath) ->
  result = relativeMdPath.replace(/\\/g, '/')
  i = result.lastIndexOf('/')
  result = result.substring(0, i)
  if result.startsWith '/'
    result = result.substring(1)
  return result

downloadNodeMessage = () ->
  return "Node #{NODE_VERSION.major}.#{NODE_VERSION.minor}.x or superior is required to provide preview. You can download it here: https://nodejs.org/\n"

class RenderingProcessManager
  intervalId: -1
  path: null

  constructor: (@maprDir, @contentDir) ->

  npmInstall: () ->
    deferred = q.defer()

    errors = []
    command = "npm"
    args = ["install"]

    stdout = (output) -> console.log "npm >", output

    stderr = (output) ->
      stream = console.error
      if output.indexOf('WARN') > 0
        stream = console.log
      else
        errors.push output

      stream "npm >", output

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
    @path = relativeMdPath
    deferred = q.defer()

    if @alreadyRunning()
      # deferred.reject message: "Rendering process is already running"
      @killPagePreview()

    @checkNodeEnvironment()
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
    @path = null

  checkNodeEnvironment: () ->
    deferred = q.defer()
    q.all([@_which("npm"), @_which("node")])
      .then (commands) =>
        filtered = commands.filter (x) -> x
        if filtered.length == 0
          @_checkVersions()
            .then (result) ->
              deferred.resolve true if result
              deferred.reject downloadNodeMessage() if !result
        else
          deferred.reject "Unable to find the following commands in your path: #{commands.join ', '}. Unable to provide preview at this time."
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

  _checkVersions: () ->
    VERSIONS = [NODE_VERSION, NPM_VERSION]
    return q.all([@_getVersion('node'), @_getVersion('npm')])
      .then (versions) =>
        versions.map (v, i) =>
          @_compareVersions(VERSIONS[i], v) >= 0
        .reduce (a, b) ->
          a && b
        , true

  _getVersion: (command) ->
    deferred = q.defer()
    args = ["--version"]
    options = {}
    returned = false

    stdout = (output) =>
      # console.log output
      returned = true
      deferred.resolve @_parseVersion(command, output)

    stderr = (output) ->
      if !returned
        returned = true
        deferred.reject {
          ok: false
          command: command
          major: 0
          minor: 0
        }

    exit = (code) ->
      if !returned
        returned = true
        deferred.reject {
          ok: false
          command: command
          major: 0
          minor: 0
        }

    proc = new BufferedProcess({command, args, options, stdout, stderr, exit})
    return deferred.promise

  _parseVersion: (command, versionString) ->
    ver = versionString.replace('v', '').split('.')
    return {
      ok: true
      command: command
      major: if ver[0] then Number.parseInt(ver[0]) else 0
      minor: if ver[1] then Number.parseInt(ver[1]) else 0
    }

  _compareVersions: (ver1, ver2) ->
    # console.log "Compare versions", ver1, ver2
    if ver1.major > ver2.major
      ret = -1
    else if ver1.major == ver2.major
      if ver1.minor > ver2.minor
        ret = -1
      else if ver1.minor == ver2.minor
        ret = 0
      else
        ret = 1
    else
      ret = 1

    # console.log "->", ret
    return ret

  alreadyRunning: () ->
    return @npmProcess? || @pageProcess?

  checkPortInUse: () ->
    return tcpPortUsed.check(TCP_PORT, '127.0.0.1')

module.exports = RenderingProcessManager
