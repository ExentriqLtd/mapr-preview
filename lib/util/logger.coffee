winston = require 'winston'
Transport = require 'winston-transport'
request = require 'request'
q = require 'q'
path = require 'path'
mkdirp = require 'mkdirp'
sysinfo = require './sysinfo'
nodeVersions = require './node-versions'

{ Directory } = require 'atom'

HttpLogConfiguration = require './http-log-configuration'
AWEConfiguration = require './configuration-adv-web-editor'
packageInfo = require '../../package.json'

logConf = new HttpLogConfiguration()
LOG_FILE = "#{packageInfo.name}.log"

aweConf = new AWEConfiguration()

class CustomConsole extends Transport
  constructor: (@opts) ->
    super(@opts)
    @name = 'myconsole'

  log: (level, msg, meta, callback) ->
    console.log "[#{level.toUpperCase()}] #{msg}", meta
    @emit('logged')
    if callback
      callback()

class CustomHttpTransport extends Transport
  constructor: (@opts) ->
    super(@opts)

  _post: (msg, meta) ->
    deferred = q.defer()

    options =
      url: @opts.endpoint
      headers:
        Authentication: @opts.authentication
      json:
        msg: msg
        meta: meta
        sysinfo: sysinfo(aweConf)

    nodeVersions.getNodeVersions().then (versions) ->
      options.json.sysinfo.node = versions[0]
      options.json.sysinfo.npm = versions[1]

      console.log "Requesting", options

      request.post options, (error, response, body) ->
        # console.log body
        try
          if error
            deferred.reject msg: "Error occurred, Resource #{options.url}", err: error
          else if response && response.statusCode != 200
            deferred.reject msg: "HTTP error #{response.statusCode}, Resource #{options.url}", code: response.statusCode
          else
            if body.response == "ok"
              deferred.resolve body
            else
              deferred.reject msg: "Invalid response", body:body
        catch e
          deferred.reject e

    return deferred.promise

  log: (level, msg, meta, callback) ->
    # setImmediate () =>
    #   @emit('logged', info)

    @_post(msg, meta).then () =>
      @emit('logged')
      if callback
        callback()
    .catch (err) -> console.log "Unable to POST log", err
    .done()

cloneDir = aweConf.get().cloneDir
logDir = path.join(cloneDir, 'logs') if cloneDir?

dirExists = (dir) ->
  if !dir
    return false
  d = new Directory(dir)
  return d.existsSync()

buildTransports = () ->
  transports = [
    new CustomConsole
  ]

  cloneDirExists = dirExists(cloneDir)

  if cloneDirExists
    if !dirExists logDir
      mkdirp.sync logDir
    transports.push new winston.transports.File({ filename: path.join(logDir, LOG_FILE) })

  if logConf.exists()
    conf = logConf.get()
    transports.push new CustomHttpTransport({ level: 'error', endpoint: conf.endpoint, authentication: conf.authentication}),

  return transports

logger = new winston.Logger
  level: 'debug',
  exitOnError: false
  transports: buildTransports()

module.exports = logger
