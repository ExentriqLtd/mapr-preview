git = require 'git-promise'
q = require 'q'
log = require './logger'
{ GitRepository } = require 'atom'

logcb = (msg, error) ->
  log[if error then 'error' else 'debug'] msg

repo = undefined
cwd = undefined
projectIndex = 0

noop = -> q.fcall -> true

atomRefresh = ->
  # repo.refreshStatus() # not public/in docs
  return

getBranches = -> q.fcall ->
  branches = local: [], remote: [], tags: []
  refs = repo.getReferences()

  for h in refs.heads
    branches.local.push h.replace('refs/heads/', '')

  for h in refs.remotes
    branches.remote.push h.replace('refs/remotes/', '')

  return branches

parseDefault = (data) -> q.fcall ->
  return true

returnAsIs = (data) -> data

callGit = (cmd, parser, nodatalog) ->
  logcb "> git #{cmd}"

  deferred = q.defer()
  git(cmd, {cwd: cwd})
    .then (data) ->
      logcb data unless nodatalog
      deferred.resolve parser(data)
    .fail (e) ->
      logcb e.stdout, true
      logcb e.message, true
      deferred.reject e

  return deferred.promise

module.exports =
  getRepository: ->
    return repo

  getBranches: getBranches

  pull: ->
    return callGit "pull", returnAsIs

  init: (path) ->
    log.debug "git::init", path
    repo = GitRepository.open path
    # console.log repo
    cwd = repo.getWorkingDirectory()
