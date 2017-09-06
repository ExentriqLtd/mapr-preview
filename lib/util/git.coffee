git = require 'git-promise'
q = require 'q'
{ GitRepository } = require 'atom'

logcb = (log, error) ->
  console[if error then 'error' else 'log'] log

repo = undefined
cwd = undefined
projectIndex = 0

noop = -> q.fcall -> true

atomRefresh = ->
  repo.refreshStatus() # not public/in docs
  return

getBranches = -> q.fcall ->
  branches = local: [], remote: [], tags: []
  refs = repo.getReferences()

  for h in refs.heads
    branches.local.push h.replace('refs/heads/', '')

  for h in refs.remotes
    branches.remote.push h.replace('refs/remotes/', '')

  return branches

# setProjectIndex = (index) ->
#   repo = undefined
#   cwd = undefined
#   projectIndex = index
#   if atom.project
#     repo = atom.project.getRepositories()[index]
#     cwd = if repo then repo.getWorkingDirectory() #prevent startup errors if repo is undefined
#   return
# setProjectIndex(projectIndex)

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
  # setProjectIndex: setProjectIndex

  getProjectIndex: ->
    return projectIndex

  getRepository: ->
    return repo

  getBranches: getBranches

  clone: (repo, target) ->
    return callGit "clone -q #{repo} #{target}", noop

  checkout: (branch, remote) ->
    return callGit "checkout #{if remote then '--track ' else ''}#{branch}", returnAsIs

  fetch: ->
    return callGit "fetch --prune", parseDefault

  pull: ->
    return callGit "pull", returnAsIs

  init: (path) ->
    console.log "git::init", path
    repo = GitRepository.open path
    console.log repo
    cwd = repo.getWorkingDirectory()
