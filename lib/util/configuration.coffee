{app} = require 'remote'
CSON = require('cson')

{File, Directory} = require 'atom'
FILE_PATH = app.getPath("userData") + "/" + "mapr-preview.cson"
keys = ["contentDir", "targetDir"]

class Configuration
  @labels:
    contentDir: "MapR.com-content Project Directory"
    targetDir: "Mapr.com Project Directory"

  @reasons:
    contentDir: "MapR.com-content Project Directory must be set"
    targetDir: "MapR.com Project Directory must be set"

  @validators:
    isValidRepo: (value) ->
      return Configuration.validators.isNotBlank(value) &&
        (Configuration.validators.isValidHttp(value) || Configuration.validators.isValidSsh(value))

    isNotBlank: (value) ->
      return value?.trim?().length > 0

    whatever: (value) ->
      return true

    isValidHttp: (value) ->
      return value.startsWith("http")

    isValidSsh: (value) ->
      return !value.startsWith("http") && value.indexOf '@' >= 0

    isEmail: (value) ->
      re = /^(([^<>()\[\]\\.,;:\s@"]+(\.[^<>()\[\]\\.,;:\s@"]+)*)|(".+"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/
      return re.test(value)

  @validationRules:
    contentDir: @validators.isNotBlank
    targetDir: @validators.isNotBlank

  constructor: () ->
    @read()

  exists: () ->
    return @confFile.existsSync()

  read: () ->
    console.log "MaprPreview::read", FILE_PATH
    @confFile = new File(FILE_PATH)
    if @exists()
      try
        @conf = CSON.parseCSONFile(FILE_PATH)
        # console.log "Read configuration: ", @conf
      catch error
        console.warn "Invalid configuration detected"
        @conf = null
    else
      @confFile.create()
      @conf = null
      return @conf

  get: () ->
    if !@conf
      @conf = {}
    # console.log "configuration::get", @conf
    return @conf

  set: (c) ->
    @conf = c
    # console.log "configuration::set", @conf
    return this

  save: () ->
    console.log "MaprPreview::save", FILE_PATH
    s = CSON.stringify(@conf)
    #@confFile.create().then =>
    @confFile.writeSync(s)
    # console.log "configuration::save", @conf

  isValid: () ->
    allKeys = @conf && Object.keys(@conf).filter (k) ->
      keys.find (j) ->
        k == j
    .length == keys.length
    return allKeys && @validateAll().length == 0

  validateAll: () ->
    return Object.keys(Configuration.validationRules).map (rule) =>
      res = Configuration.validationRules[rule](@conf[rule])
      return if res then null else rule
    .filter (x) -> x

  isStringEmpty: (s) ->
    return !(s && s.trim && s.trim().length > 0)

module.exports = Configuration
