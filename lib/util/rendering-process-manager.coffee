{BufferedProcess} = require('atom')
q = require 'q'

class RenderingProcessManager

  constructor: (@maprDir, @contentDir) ->
    console.log @maprDir, @contentDir

  pagePreview: (relativeMdPath) ->
    deferred = q.defer()
    returned = false
    errors = []
    if @pageProcess?
      deferred.reject message: "Rendering process is already running"
    else
      command = "node"
      args = ["preview.js", "#{relativeMdPath}", "#{@contentDir}"]
      stdout = (output) ->
        # console.log "Got line", output
        if !returned && output.trim().startsWith("[metalsmith-serve]")
          window.setTimeout () ->
            returned = true
            deferred.resolve true
          , 2500
      stderr = (output) ->
        console.error output
        errors.push output
      exit = (code) ->
        console.log("pagePreview exited with #{code}")
        if code && code > 0 && !returned
          deferred.reject errors.join "\n"

      options =
        cwd: @maprDir
      @pageProcess = new BufferedProcess({command, args, options, stdout, stderr, exit})

    return deferred.promise

  killPagePreview: () ->
    @pageProcess?.kill()
    @pageProcess = null

module.exports = RenderingProcessManager
