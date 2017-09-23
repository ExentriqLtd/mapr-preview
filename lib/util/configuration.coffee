{app} = require 'remote'
CSON = require('cson')
path = require('path')

AWEConfiguration = require './configuration-adv-web-editor'

{File, Directory} = require 'atom'

FILE_PATH = path.join(app.getPath("userData"), "mapr-preview.cson")

# Project folders with contents allowed in preview
LOCALES = ['en', 'fr', 'ja', 'ko']

getRepoName = (uri) ->
  tmp = uri.split('/')
  name = tmp[tmp.length-1]
  tmp = name.split('.')
  [..., last] = tmp
  if last is 'git'
    name = tmp[...-1].join('.')
  else
    name

class Configuration
  @labels:
    repoUrl: "MapR.com Project Clone URL"
    targetDir: "MapR.com Project Directory"
    contentDir: "MapR.com-content Project Directory"
    repoOwner: "BitBucket Repository Owner"
    username: "BitBucket API Username"
    password: "BitBucket API Password"

  @reasons:
    repoUrl: "MapR.com Project Clone URL must be a valid SSH repository"
    contentDir: "MapR.com-content Project Directory must exist"
    targetDir: "MapR.com Project Directory must be set"
    repoOwner: "BitBucket Repository Owner must be set"
    username: "BitBucket API Username must be set"
    password: "BitBucket API Password must be set"

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
    dirExists: (value) ->
      dir = new Directory(value)
      return dir.existsSync()

  @validationRules:
    repoUrl: @validators.isValidRepo
    contentDir: @validators.dirExists
    targetDir: @validators.isNotBlank
    username: @validators.isNotBlank
    password: @validators.isNotBlank
    repoOwner: @validators.isNotBlank

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
      @conf = {
        repoUrl: ''
      }
      return @conf

  get: () ->
    if !@conf
      @conf = {
          ####
          # Empty Object
          # initialization
          ####
      }

    console.log "configuration::get", @conf
    return @conf

  set: (c) ->
    @conf = c
    # console.log "configuration::set", @conf
    return this

  setValues: (values) ->
    Object.keys(values).forEach (key) => @conf[key] = values[key]

  save: () ->
    console.log "MaprPreview::save", FILE_PATH
    s = CSON.stringify(@conf)
    #@confFile.create().then =>
    @confFile.writeSync(s)
    # console.log "configuration::save", @conf

  acquireFromAwe: () ->
    aweConf = new AWEConfiguration()
    if !(aweConf.exists() && aweConf.isValid())
      return

    innerAweConf = aweConf.get()

    @conf.contentDir = path.join(innerAweConf.cloneDir, getRepoName(innerAweConf.repoUrl))
    @conf.targetDir = innerAweConf.cloneDir
    # @conf.repoOwner = innerAweConf.repoOwner
    # @conf.username = innerAweConf.repoUsername
    # @conf.password = innerAweConf.password

  isAweConfValid: () ->
    aweConf = new AWEConfiguration()
    return aweConf.exists() && aweConf.isValid()

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

  getTargetDir: () ->
    return path.join(@conf.targetDir, getRepoName(@conf.repoUrl))

  getRepoName: getRepoName

  shouldClone: () ->
    return !Configuration.validators.dirExists(@getTargetDir())

  isPathFromProject: (path) ->
    root = @conf.contentDir
    return path.indexOf(root) >= 0

  #strip down mapr.com-content path from the given path
  relativePath: (path) ->
    root = @conf.contentDir
    if root.endsWith path.sep
      root = root.substring(0, root.length-2)
    return path.replace(root, '')

  isPreviewAllowed: (filePath) ->
    # console.log 'Is preview allowed?', filePath
    fromProject = @isPathFromProject(filePath)
    if !fromProject
      # console.log 'No, path is not from project'
      return false

    if !filePath.endsWith '.md'
      # console.log 'No, it is not a markdown'
      return false

    folders = @relativePath(filePath).split(path.sep).filter (x) -> x
    # console.log folders
    if folders[0] in LOCALES
      # console.log 'Yep.'
      return true
    else
      # console.log 'Nope.'
      return false

keys = Object.keys(Configuration.labels)
module.exports = Configuration
