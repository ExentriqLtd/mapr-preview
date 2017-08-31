{BufferedProcess} = require('atom')
q = require 'q'

class RenderingProcessManager

  constructor: (@maprDir, @contentDir) ->
    console.log @maprDir, @contentDir

  pagePreview: (relativeMdPath) ->
    deferred = q.defer()
    returned = false
    if @pageProcess?
      return

    command = "node"
    args = ["preview.js", "#{relativeMdPath}", "#{@contentDir}"]
    stdout = (output) ->
      if !returned && output.trim().startsWith("[metalsmith]")
        returned = true
        deferred.resolve true
    stderr = (output) ->
      console.error output
    exit = (code) -> console.log("pagePreview exited with #{code}")
    options =
      cwd: @maprDir
    @pageProcess = new BufferedProcess({command, args, options, stdout, stderr, exit})

    return deferred.promise

  killPagePreview: () ->
    @pageProcess?.kill()
    @pageProcess = null

module.exports = RenderingProcessManager
