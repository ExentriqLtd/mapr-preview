q = require 'q'
{BufferedProcess} = require('atom')
which = require 'which'

NODE_VERSION = major: 6, minor: 5
NPM_VERSION = major: 3, minor: 8

utils = {}

utils.downloadNodeMessage = () ->
  return "Node #{NODE_VERSION.major}.#{NODE_VERSION.minor}.x or superior is required to provide preview. You can download it here: https://nodejs.org/\n"

utils.checkNodeEnvironment = () ->
  deferred = q.defer()
  q.all([utils.which("npm"), utils.which("node")])
    .then (commands) ->
      filtered = commands.filter (x) -> x
      if filtered.length == 0
        utils.checkVersions()
          .then (result) ->
            deferred.resolve true if result
            deferred.reject nodeVersions.downloadNodeMessage() if !result
      else
        deferred.reject "Unable to find the following commands in your path: #{commands.join ', '}. Unable to provide preview at this time."
  return deferred.promise

utils.which = (command) ->
  deferred = q.defer()

  which command, (err, result) ->
    if err
      deferred.resolve command
    else
      deferred.resolve null

  return deferred.promise

utils.checkVersions = () ->
  VERSIONS = [NODE_VERSION, NPM_VERSION]
  utils.getNodeVersions()
    .then (versions) ->
      versions.map (v, i) ->
        utils.compareVersions(VERSIONS[i], v) >= 0
      .reduce (a, b) ->
        a && b
      , true

utils.getNodeVersions = () ->
  return q.all([utils.getVersion('node'), utils.getVersion('npm')])

utils.getVersion = (command) ->
  deferred = q.defer()
  args = ["--version"]
  options = {}
  returned = false

  stdout = (output) ->
    # log.debug output
    returned = true
    deferred.resolve utils.parseVersion(command, output)

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

utils.parseVersion = (command, versionString) ->
  ver = versionString.replace('v', '').split('.')
  return {
    ok: true
    command: command
    major: if ver[0] then Number.parseInt(ver[0]) else 0
    minor: if ver[1] then Number.parseInt(ver[1]) else 0
  }

utils.compareVersions = (ver1, ver2) ->
  # log.debug "Compare versions", ver1, ver2
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

  # log.debug "->", ret
  return ret

module.exports = utils
